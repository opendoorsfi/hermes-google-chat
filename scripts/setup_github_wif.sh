#!/usr/bin/env bash
# Kertaluontoinen: GitHub Actions → GCP WIF projektille od-kansiot (hermes-google-chat).
#
#   export GCP_PROJECT=od-kansiot
#   export HERMES_GITHUB_REPO=opendoorsfi/hermes-google-chat
#   bash scripts/setup_github_wif.sh
#
# Luo tarvittaessa deploy-SA + WIF pool. Tulostaa GitHub secrets -arvot.

set -euo pipefail

GCP_PROJECT="${GCP_PROJECT:-od-kansiot}"
POOL="${WIF_POOL:-github-pool}"
PROVIDER="${WIF_PROVIDER:-github-provider}"
DEPLOY_SA="${DEPLOY_SA:-github-hermes-deploy@${GCP_PROJECT}.iam.gserviceaccount.com}"
HERMES_GITHUB_REPO="${HERMES_GITHUB_REPO:-opendoorsfi/hermes-google-chat}"
HERMES_GITHUB_ORG="${HERMES_GITHUB_ORG:-${HERMES_GITHUB_REPO%%/*}}"
WIF_ATTRIBUTE_MAPPING="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner"
# GCP vaatii attribute-condition create-oidc:ssä (2024+). assertion.* viittaa GitHub OIDC -claimiin.
WIF_ATTRIBUTE_CONDITION="assertion.repository=='${HERMES_GITHUB_REPO}' && assertion.repository_owner=='${HERMES_GITHUB_ORG}'"

PROJECT_NUMBER="$(gcloud projects describe "${GCP_PROJECT}" --format='value(projectNumber)')"
WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"
PRINCIPAL_HERMES="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/${HERMES_GITHUB_REPO}"

echo "==> Projekti: ${GCP_PROJECT} (${PROJECT_NUMBER})"

if ! gcloud iam service-accounts describe "${DEPLOY_SA}" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "==> Luodaan deploy-SA: ${DEPLOY_SA}"
  gcloud iam service-accounts create github-hermes-deploy \
    --project="${GCP_PROJECT}" \
    --display-name="GitHub Actions Hermes Google Chat deploy"
fi

if ! gcloud iam workload-identity-pools describe "${POOL}" \
  --project="${GCP_PROJECT}" --location=global &>/dev/null; then
  echo "==> Luodaan WIF pool: ${POOL}"
  gcloud iam workload-identity-pools create "${POOL}" \
    --project="${GCP_PROJECT}" \
    --location=global \
    --display-name="GitHub Actions pool"
fi

if ! gcloud iam workload-identity-pools providers describe "${PROVIDER}" \
  --project="${GCP_PROJECT}" --location=global \
  --workload-identity-pool="${POOL}" &>/dev/null; then
  echo "==> Luodaan WIF provider: ${PROVIDER}"
  gcloud iam workload-identity-pools providers create-oidc "${PROVIDER}" \
    --project="${GCP_PROJECT}" \
    --location=global \
    --workload-identity-pool="${POOL}" \
    --display-name="GitHub provider" \
    --attribute-mapping="${WIF_ATTRIBUTE_MAPPING}" \
    --attribute-condition="${WIF_ATTRIBUTE_CONDITION}" \
    --issuer-uri="https://token.actions.githubusercontent.com"
else
  echo "==> WIF provider ${PROVIDER} on jo olemassa — päivitetään condition"
  gcloud iam workload-identity-pools providers update-oidc "${PROVIDER}" \
    --project="${GCP_PROJECT}" \
    --location=global \
    --workload-identity-pool="${POOL}" \
    --attribute-mapping="${WIF_ATTRIBUTE_MAPPING}" \
    --attribute-condition="${WIF_ATTRIBUTE_CONDITION}"
fi

echo "==> IAM: ${HERMES_GITHUB_REPO} → ${DEPLOY_SA}"
gcloud iam service-accounts add-iam-policy-binding "${DEPLOY_SA}" \
  --project="${GCP_PROJECT}" \
  --role=roles/iam.workloadIdentityUser \
  --member="${PRINCIPAL_HERMES}" \
  --quiet

echo ""
echo "OK — aseta GitHub secrets + registry (config/tenants/registry.json → wif_provider):"
echo "  GCP_WIF_PROVIDER=${WIF_PROVIDER}"
echo "  GCP_DEPLOY_SA_EMAIL=${DEPLOY_SA}"
echo ""
echo "  gh secret set GCP_WIF_PROVIDER --repo ${HERMES_GITHUB_REPO} --body '${WIF_PROVIDER}'"
echo "  gh secret set GCP_DEPLOY_SA_EMAIL --repo ${HERMES_GITHUB_REPO} --body '${DEPLOY_SA}'"
echo ""
echo "  Päivitä registry: \"wif_provider\": \"${WIF_PROVIDER}\""
