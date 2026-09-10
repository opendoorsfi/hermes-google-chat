#!/usr/bin/env bash
# KERTALUONTOINEN bootstrap (gcloud auth). Jatkossa deploy GitHub Actionsista:
#   push main → workflow "Deploy Hermes Gateway"
#   tai Actions → Deploy Hermes Gateway → Run workflow
#
#   gcloud auth login --no-launch-browser
#   export GCP_PROJECT=od-azuracast-sync
#   export GCP_REGION=europe-north1
#   bash hermes-google-chat/scripts/bootstrap_from_terminal.sh
#
# WIF + GitHub secrets (kerran, repo admin):
#   bash hermes-google-chat/scripts/setup_github_wif.sh
#   gh secret set GCP_WIF_PROVIDER ...  (ks. docs/GITHUB_SECRETS.md)

set -euo pipefail

GCLOUD="${GCLOUD:-gcloud}"
if ! command -v "${GCLOUD}" >/dev/null 2>&1; then
  for candidate in \
    /home/ubuntu/google-cloud-sdk/google-cloud-sdk/bin/gcloud \
    "$HOME/google-cloud-sdk/bin/gcloud"; do
    if [[ -x "${candidate}" ]]; then
      GCLOUD="${candidate}"
      PATH="$(dirname "${candidate}"):${PATH}"
      export PATH
      break
    fi
  done
fi
if ! command -v "${GCLOUD}" >/dev/null 2>&1; then
  echo "VIRHE: gcloud ei löydy. Asenna: https://cloud.google.com/sdk/docs/install"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GCP_PROJECT="${GCP_PROJECT:-od-azuracast-sync}"
GCP_REGION="${GCP_REGION:-europe-north1}"
HERMES_GITHUB_REPO="${HERMES_GITHUB_REPO:-opendoorsfi/hermes-google-chat}"
SET_GH_SECRETS=false

for arg in "$@"; do
  case "$arg" in
    --set-github-secrets) SET_GH_SECRETS=true ;;
  esac
done

if ! "${GCLOUD}" auth list --filter=status:ACTIVE --format='value(account)' | grep -q .; then
  echo "VIRHE: gcloud ei ole kirjautuneena."
  echo "  ${GCLOUD} auth login --no-launch-browser"
  exit 1
fi

"${GCLOUD}" config set project "${GCP_PROJECT}" >/dev/null
echo "==> GCP projekti: ${GCP_PROJECT} (${GCP_REGION})"

export GCP_PROJECT GCP_REGION
bash "${ROOT}/infra/setup_gcp.sh"

export HERMES_CHAT_TRANSPORT="${HERMES_CHAT_TRANSPORT:-http}"

echo "==> Deploy Cloud Run HTTP-moodissa (LLM: hermes-llm-api-key Secret Managerissa)"
bash "${ROOT}/deploy/cloudrun/deploy.sh" || {
  echo "Deploy epäonnistui — tarkista hermes-llm-api-key ja Chat-asetukset."
  exit 1
}

bash "${ROOT}/scripts/verify_pubsub.sh" || true

if [[ "${SET_GH_SECRETS}" == true ]]; then
  if ! gh auth status >/dev/null 2>&1; then
    echo "gh ei kirjautuneena — ohitetaan GitHub secrets"
    exit 0
  fi
  WIF="${GCP_WIF_PROVIDER:-}"
  SA="${GCP_DEPLOY_SA_EMAIL:-}"
  if [[ -z "${WIF}" || -z "${SA}" ]]; then
    echo "Aseta GCP_WIF_PROVIDER ja GCP_DEPLOY_SA_EMAIL ympäristöön ennen --set-github-secrets"
    exit 1
  fi
  gh secret set GCP_WIF_PROVIDER --repo "${HERMES_GITHUB_REPO}" --body "${WIF}"
  gh secret set GCP_DEPLOY_SA_EMAIL --repo "${HERMES_GITHUB_REPO}" --body "${SA}"
  echo "GitHub secrets asetettu (${HERMES_GITHUB_REPO})."
fi

echo ""
echo "OK — seuraavaksi Chat API Console → Connection settings → HTTP endpoint URL:"
if [[ -f "${ROOT}/out/deploy.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT}/out/deploy.env"
  echo "  ${CHAT_HTTP_EVENTS_URL:-<aja deploy uudelleen>}"
else
  echo "  (out/deploy.env puuttuu — tarkista deploy/cloudrun/deploy.sh)"
fi
echo "Smoke: lähetä 'hola' spaceen/DM:ään."
