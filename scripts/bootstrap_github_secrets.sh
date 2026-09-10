#!/usr/bin/env bash
# Aseta GitHub Actions -secrets + (valinnainen) WIF hermes-google-chat -repoon.
#
# Aja org-admin / repo-admin -tilillä (fine-grained PAT: Contents Read/Write):
#   gh auth login
#   bash scripts/bootstrap_github_secrets.sh
#
# Cloud Agent -integraatiotokenilla ei yleensä ole oikeutta secrets/workflow_dispatch.
# Arvot ovat repossa docs/CREATE_REPO.md — WIF provider path ei ole salainen.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_GITHUB_REPO="${HERMES_GITHUB_REPO:-opendoorsfi/hermes-google-chat}"
GCP_PROJECT="${GCP_PROJECT:-od-azuracast-sync}"

# Lähteet: docs/CREATE_REPO.md, docs/GITHUB_SECRETS.md
GCP_WIF_PROVIDER="${GCP_WIF_PROVIDER:-projects/381850973284/locations/global/workloadIdentityPools/github-pool/providers/github-provider}"
GCP_DEPLOY_SA_EMAIL="${GCP_DEPLOY_SA_EMAIL:-github-azuracast-deploy@od-azuracast-sync.iam.gserviceaccount.com}"

RUN_WIF="${RUN_WIF:-auto}"   # auto | yes | no
GRANT_TENANT_IAM="${GRANT_TENANT_IAM:-}"  # pilkulla: hermes-alice,hermes-team

usage() {
  cat <<EOF
Usage: bash scripts/bootstrap_github_secrets.sh [options]

  --wif              Aja scripts/setup_github_wif.sh (vaatii gcloud auth)
  --no-wif           Älä aja WIF-skriptiä
  --grant-tenants A,B  Anna deploy-SA:lle IAM tenant-projekteissa
  --dry-run          Tulosta arvot, älä kirjoita

Ympäristö: GCP_WIF_PROVIDER, GCP_DEPLOY_SA_EMAIL, HERMES_GITHUB_REPO, GCP_PROJECT
EOF
}

DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wif) RUN_WIF=yes; shift ;;
    --no-wif) RUN_WIF=no; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --grant-tenants)
      GRANT_TENANT_IAM="${2:-}"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Tuntematon: $1"; usage; exit 1 ;;
  esac
done

echo "==> Repo: ${HERMES_GITHUB_REPO}"
echo "    GCP_WIF_PROVIDER=${GCP_WIF_PROVIDER}"
echo "    GCP_DEPLOY_SA_EMAIL=${GCP_DEPLOY_SA_EMAIL}"

if [[ "${DRY_RUN}" == true ]]; then
  echo "(dry-run — ei kirjoiteta)"
  exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "VIRHE: gh ei kirjautuneena. Aja: gh auth login"
  exit 1
fi

if ! gh repo view "${HERMES_GITHUB_REPO}" --json name >/dev/null 2>&1; then
  echo "VIRHE: gh ei näe repoa ${HERMES_GITHUB_REPO}"
  exit 1
fi

echo "==> GitHub secrets"
if gh secret set GCP_WIF_PROVIDER --repo "${HERMES_GITHUB_REPO}" --body "${GCP_WIF_PROVIDER}"; then
  echo "OK: GCP_WIF_PROVIDER"
else
  echo "VIRHE: GCP_WIF_PROVIDER — tokenilla ei repo secrets -oikeutta?"
  exit 1
fi

if gh secret set GCP_DEPLOY_SA_EMAIL --repo "${HERMES_GITHUB_REPO}" --body "${GCP_DEPLOY_SA_EMAIL}"; then
  echo "OK: GCP_DEPLOY_SA_EMAIL"
else
  echo "VIRHE: GCP_DEPLOY_SA_EMAIL"
  exit 1
fi

# Varmista (list voi olla 403 joillakin tokeneilla — secret set riittää)
if gh secret list --repo "${HERMES_GITHUB_REPO}" 2>/dev/null | grep -q GCP_WIF_PROVIDER; then
  echo "OK: secrets listattu repossa"
fi

if [[ "${RUN_WIF}" == "auto" ]]; then
  if command -v gcloud >/dev/null 2>&1 && gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q .; then
    RUN_WIF=yes
  else
    RUN_WIF=no
  fi
fi

if [[ "${RUN_WIF}" == "yes" ]]; then
  echo "==> WIF (setup_github_wif.sh)"
  export GCP_PROJECT HERMES_GITHUB_REPO
  bash "${ROOT}/scripts/setup_github_wif.sh"
else
  echo "==> WIF ohitettu (gcloud auth puuttuu tai --no-wif). Aja myöhemmin:"
  echo "    export HERMES_GITHUB_REPO=${HERMES_GITHUB_REPO}"
  echo "    bash scripts/setup_github_wif.sh"
fi

if [[ -n "${GRANT_TENANT_IAM}" ]]; then
  echo "==> Deploy-SA IAM tenant-projekteissa"
  IFS=',' read -ra PROJECTS <<< "${GRANT_TENANT_IAM}"
  for proj in "${PROJECTS[@]}"; do
    proj="${proj// /}"
    [[ -n "${proj}" ]] || continue
    for role in roles/serviceusage.serviceUsageAdmin roles/iam.serviceAccountAdmin; do
      echo "    ${proj} ← ${GCP_DEPLOY_SA_EMAIL} (${role})"
      gcloud projects add-iam-policy-binding "${proj}" \
        --member="serviceAccount:${GCP_DEPLOY_SA_EMAIL}" \
        --role="${role}" \
        --quiet
    done
  done
fi

cat <<EOF

==> Valmis — seuraavaksi

1. Luo tenant GCP (Actions tai paikallisesti):
   https://github.com/${HERMES_GITHUB_REPO}/actions/workflows/tenant-gcp.yml
   → Run workflow → tenant=alice, funnel_base_url=https://<host>.ts.net

2. Host + Chat: docs/GOOGLE_CHAT_INSTALL.md

EOF
