#!/usr/bin/env bash
# Lue GCP-projekti + deploy-SA registrystä → GITHUB_ENV (GitHub Actions).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "VIRHE: GITHUB_ENV puuttuu (aja vain GitHub Actionsissa)" >&2
  exit 1
fi

eval "$(python3 "${ROOT}/scripts/chat_registry.py" github-env)"
{
  echo "GCP_PROJECT=${GCP_PROJECT}"
  echo "GCP_DEPLOY_SA_EMAIL=${GCP_DEPLOY_SA_EMAIL}"
  if [[ -n "${GCP_WIF_PROVIDER:-}" ]]; then
    echo "GCP_WIF_PROVIDER=${GCP_WIF_PROVIDER}"
  fi
} >> "${GITHUB_ENV}"

echo "OK: GCP_PROJECT=${GCP_PROJECT} SA=${GCP_DEPLOY_SA_EMAIL}"
