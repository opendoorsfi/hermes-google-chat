#!/usr/bin/env bash
# Deploy Hermes Pub/Sub gateway to Cloud Run (ei vaadi self-hosted runneria).
#
#   bash scripts/deploy_pubsub_gateway.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

GCP_PROJECT="${GCP_PROJECT:-$(python3 scripts/chat_registry.py hub-json | python3 -c "import json,sys; print(json.load(sys.stdin)['gcp_project'])")}"
HUB="$(python3 scripts/chat_registry.py hub-json)"
SUB_FULL="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['pubsub_subscription_full'])" "${HUB}")"
ALLOWED="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['allowed_users'])" "${HUB}")"

export GCP_PROJECT
export HERMES_CHAT_TRANSPORT=pubsub
export HERMES_GATEWAY_MODE=embedded
export GOOGLE_CHAT_PROJECT_ID="${GCP_PROJECT}"
export GOOGLE_CHAT_SUBSCRIPTION_NAME="${SUB_FULL}"
export GOOGLE_CHAT_ALLOWED_USERS="${ALLOWED}"

echo "==> Pub/Sub gateway → Cloud Run"
echo "    project:      ${GCP_PROJECT}"
echo "    subscription: ${SUB_FULL}"
echo "    allowed:      ${ALLOWED}"

bash "${ROOT}/infra/setup_gcp.sh"
bash "${ROOT}/deploy/cloudrun/deploy.sh"
