#!/usr/bin/env bash
# Deploy Hermes Pub/Sub gateway → Cloud Run (ei vaadi Macia / self-hosted runneria).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HUB="$(python3 "${ROOT}/scripts/chat_registry.py" hub-json)"
GCP_PROJECT="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['gcp_project'])" "${HUB}")"
GOOGLE_CHAT_SUBSCRIPTION_NAME="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['pubsub_subscription_full'])" "${HUB}")"
GOOGLE_CHAT_ALLOWED_USERS="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['allowed_users'])" "${HUB}")"
CHAT_PUBSUB_SUB="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['pubsub_sub'])" "${HUB}")"

export GCP_PROJECT GCP_REGION="${GCP_REGION:-europe-north1}"
export CLOUDSDK_CORE_PROJECT="${GCP_PROJECT}"
export CLOUDSDK_PROJECT="${GCP_PROJECT}"
export GCLOUD_PROJECT="${GCP_PROJECT}"
export GOOGLE_CLOUD_PROJECT="${GCP_PROJECT}"
export HERMES_CHAT_TRANSPORT=pubsub HERMES_GATEWAY_MODE=embedded
export GOOGLE_CHAT_PROJECT_ID="${GCP_PROJECT}"
export GOOGLE_CHAT_SUBSCRIPTION_NAME GOOGLE_CHAT_ALLOWED_USERS CHAT_PUBSUB_SUB
if command -v gcloud >/dev/null 2>&1; then
  gcloud config set project "${GCP_PROJECT}" >/dev/null
fi

echo "==> Cloud Run Pub/Sub gateway"
echo "    project:      ${GCP_PROJECT}"
echo "    subscription: ${GOOGLE_CHAT_SUBSCRIPTION_NAME}"
echo "    allowed:      ${GOOGLE_CHAT_ALLOWED_USERS}"

bash "${ROOT}/infra/setup_gcp.sh"
bash "${ROOT}/deploy/cloudrun/deploy.sh"
