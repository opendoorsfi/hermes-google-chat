#!/usr/bin/env bash
# Kertaluontoinen: salli GitHub Actions → GCP (WIF) Hermes-google-chat repolle.
#
#   export GCP_PROJECT=od-azuracast-sync
#   export HERMES_GITHUB_REPO=opendoorsfi/hermes-google-chat
#   bash scripts/setup_github_wif.sh

set -euo pipefail

GCP_PROJECT="${GCP_PROJECT:-od-azuracast-sync}"
POOL="${WIF_POOL:-github-pool}"
PROVIDER="${WIF_PROVIDER:-github-provider}"
DEPLOY_SA="${DEPLOY_SA:-github-azuracast-deploy@${GCP_PROJECT}.iam.gserviceaccount.com}"
HERMES_GITHUB_REPO="${HERMES_GITHUB_REPO:-opendoorsfi/hermes-google-chat}"
AZURACAST_REPO="${AZURACAST_REPO:-opendoorsfi/azuracast-sync}"
MODERATE_REPO="${MODERATE_REPO:-opendoorsfi/moderate}"

PROJECT_NUMBER="$(gcloud projects describe "${GCP_PROJECT}" --format='value(projectNumber)')"
WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"
PRINCIPAL_HERMES="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/${HERMES_GITHUB_REPO}"

echo "==> WIF: salli ${HERMES_GITHUB_REPO} (+ existing repos)"
gcloud iam workload-identity-pools providers update-oidc "${PROVIDER}" \
  --project="${GCP_PROJECT}" \
  --location=global \
  --workload-identity-pool="${POOL}" \
  --attribute-condition="assertion.repository=='${AZURACAST_REPO}' || assertion.repository=='${MODERATE_REPO}' || assertion.repository=='${HERMES_GITHUB_REPO}'"

echo "==> IAM: ${HERMES_GITHUB_REPO} → ${DEPLOY_SA}"
gcloud iam service-accounts add-iam-policy-binding "${DEPLOY_SA}" \
  --project="${GCP_PROJECT}" \
  --role=roles/iam.workloadIdentityUser \
  --member="${PRINCIPAL_HERMES}" \
  --quiet 2>/dev/null || \
gcloud iam service-accounts add-iam-policy-binding "${DEPLOY_SA}" \
  --project="${GCP_PROJECT}" \
  --role=roles/iam.workloadIdentityUser \
  --member="${PRINCIPAL_HERMES}"

echo ""
echo "OK — aseta GitHub secrets repoon ${HERMES_GITHUB_REPO}:"
echo "  GCP_WIF_PROVIDER=${WIF_PROVIDER}"
echo "  GCP_DEPLOY_SA_EMAIL=${DEPLOY_SA}"
echo ""
echo "  gh secret set GCP_WIF_PROVIDER --repo ${HERMES_GITHUB_REPO} --body '${WIF_PROVIDER}'"
echo "  gh secret set GCP_DEPLOY_SA_EMAIL --repo ${HERMES_GITHUB_REPO} --body '${DEPLOY_SA}'"
