#!/usr/bin/env bash
# Kerran (GCP Owner): Pub/Sub + deploy-SA + WIF uudelle Gmail-GCP-projektille.
#
#   export GCP_PROJECT=opendoors-hermes-chat
#   bash scripts/bootstrap_gcp_project.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GCP_PROJECT="${GCP_PROJECT:-$(python3 "${ROOT}/scripts/chat_registry.py" hub-json | python3 -c "import json,sys; print(json.load(sys.stdin)['gcp_project'])")}"
export GCP_PROJECT HERMES_CHAT_TRANSPORT=pubsub

echo "==> Hermes GCP bootstrap: ${GCP_PROJECT}"
bash "${ROOT}/infra/setup_gcp.sh"
bash "${ROOT}/scripts/grant_deploy_sa_chat.sh"
bash "${ROOT}/scripts/setup_github_wif.sh"
