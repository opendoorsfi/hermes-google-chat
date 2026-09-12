#!/usr/bin/env bash
# Lataa GCP-projekti registrystä GitHub Actionsiin.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REG="${ROOT}/config/registry.json"

export GCP_PROJECT
GCP_PROJECT="$(python3 -c "import json; print(json.load(open('${REG}'))['gcp_project'])")"
export GCP_REGION
GCP_REGION="$(python3 -c "import json; print(json.load(open('${REG}')).get('gcp_region','europe-north1'))")"
export GCP_WIF_PROVIDER
GCP_WIF_PROVIDER="$(python3 -c "import json; print(json.load(open('${REG}')).get('wif_provider',''))")"
export GCP_DEPLOY_SA_EMAIL
GCP_DEPLOY_SA_EMAIL="$(python3 -c "import json; print(json.load(open('${REG}')).get('github_deploy_sa',''))")"

echo "GCP_PROJECT=${GCP_PROJECT}"
echo "GCP_REGION=${GCP_REGION}"
