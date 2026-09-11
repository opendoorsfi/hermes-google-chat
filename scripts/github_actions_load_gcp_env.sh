#!/usr/bin/env bash
# Lue GCP-projekti + deploy-SA registrystä → GITHUB_ENV + GITHUB_OUTPUT.
#
# setup-gcloud / org-secret voi asettaa GCP_PROJECT=od-kansiot. Aja:
#   1) ennen auth (step outputs → project_id)
#   2) uudestaan setup-gcloudin jälkeen (pin last-write-wins)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "VIRHE: GITHUB_ENV puuttuu (aja vain GitHub Actionsissa)" >&2
  exit 1
fi

eval "$(python3 "${ROOT}/scripts/chat_registry.py" github-env)"

pin() {
  local file="$1"
  {
    echo "GCP_PROJECT=${GCP_PROJECT}"
    echo "GCP_DEPLOY_SA_EMAIL=${GCP_DEPLOY_SA_EMAIL}"
    echo "CLOUDSDK_CORE_PROJECT=${GCP_PROJECT}"
    echo "CLOUDSDK_PROJECT=${GCP_PROJECT}"
    echo "GCLOUD_PROJECT=${GCP_PROJECT}"
    echo "GOOGLE_CLOUD_PROJECT=${GCP_PROJECT}"
    if [[ -n "${GCP_WIF_PROVIDER:-}" ]]; then
      echo "GCP_WIF_PROVIDER=${GCP_WIF_PROVIDER}"
    fi
  } >> "${file}"
}

pin "${GITHUB_ENV}"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  pin "${GITHUB_OUTPUT}"
fi

if command -v gcloud >/dev/null 2>&1; then
  gcloud config set project "${GCP_PROJECT}" >/dev/null 2>&1 || true
fi

echo "OK: GCP_PROJECT=${GCP_PROJECT} SA=${GCP_DEPLOY_SA_EMAIL}"
