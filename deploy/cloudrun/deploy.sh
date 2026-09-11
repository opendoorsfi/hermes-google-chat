#!/usr/bin/env bash
# Deploy hermes-gateway to Cloud Run (HTTP tai Pub/Sub Chat inbound).
#
# Embedded (oletus — LLM Cloud Runissa):
#   export GCP_PROJECT=od-azuracast-sync
#   bash deploy/cloudrun/deploy.sh
#
# Proxy (Chat relay → olemassa oleva Hermes API server):
#   export HERMES_GATEWAY_MODE=proxy
#   export GATEWAY_PROXY_URL=https://your-hermes.example.com:8642
#   export GATEWAY_PROXY_KEY=<same as remote API_SERVER_KEY>
#   bash deploy/cloudrun/deploy.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVICE_NAME="${SERVICE_NAME:-hermes-gateway}"
GCP_PROJECT="${GCP_PROJECT:?Set GCP_PROJECT}"
GCP_REGION="${GCP_REGION:-europe-north1}"
SA_NAME="${SA_NAME:-hermes-chat-bot}"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
AR_REPO="${AR_REPO:-hermes-google-chat}"
IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${AR_REPO}/${SERVICE_NAME}:latest"
HERMES_CHAT_TRANSPORT="${HERMES_CHAT_TRANSPORT:-http}"
HERMES_GATEWAY_MODE="${HERMES_GATEWAY_MODE:-embedded}"
GATEWAY_PROXY_URL="${GATEWAY_PROXY_URL:-}"
CHAT_HTTP_PATH="/api/platforms/google_chat/events"

if [[ "${HERMES_GATEWAY_MODE}" == "proxy" && -z "${GATEWAY_PROXY_URL}" ]]; then
  echo "VIRHE: HERMES_GATEWAY_MODE=proxy vaatii GATEWAY_PROXY_URL (olemassa oleva Hermes API server)"
  exit 1
fi

GOOGLE_CHAT_PROJECT_ID="${GOOGLE_CHAT_PROJECT_ID:-${GCP_PROJECT}}"
GOOGLE_CHAT_SUBSCRIPTION_NAME="${GOOGLE_CHAT_SUBSCRIPTION_NAME:-}"
CHAT_PUBSUB_SUB="${CHAT_PUBSUB_SUB:-hermes-chat-events-sub}"
GOOGLE_CHAT_ALLOWED_USERS="${GOOGLE_CHAT_ALLOWED_USERS:-}"
GOOGLE_CHAT_HOME_CHANNEL="${GOOGLE_CHAT_HOME_CHANNEL:-}"
GOOGLE_CHAT_BOOTSTRAP_SPACES="${GOOGLE_CHAT_BOOTSTRAP_SPACES:-${GOOGLE_CHAT_HOME_CHANNEL}}"

if [[ "${HERMES_CHAT_TRANSPORT}" == "pubsub" && -z "${GOOGLE_CHAT_SUBSCRIPTION_NAME}" ]]; then
  GOOGLE_CHAT_SUBSCRIPTION_NAME="projects/${GOOGLE_CHAT_PROJECT_ID}/subscriptions/${CHAT_PUBSUB_SUB}"
fi

echo "==> Build ${IMAGE} (Cloud Build)"
gcloud builds submit "${ROOT}" \
  --project="${GCP_PROJECT}" \
  --config="${ROOT}/deploy/cloudbuild.yaml" \
  --substitutions="_IMAGE=${IMAGE}" \
  --timeout=1200s \
  --quiet

ENV_VARS="HERMES_CHAT_TRANSPORT=${HERMES_CHAT_TRANSPORT}"
ENV_VARS+=",HERMES_GATEWAY_MODE=${HERMES_GATEWAY_MODE}"
ENV_VARS+=",GOOGLE_CHAT_PROJECT_ID=${GOOGLE_CHAT_PROJECT_ID}"
if [[ -n "${GATEWAY_PROXY_URL}" ]]; then
  ENV_VARS+=",GATEWAY_PROXY_URL=${GATEWAY_PROXY_URL}"
fi
ENV_VARS+=",GOOGLE_CHAT_MAX_MESSAGES=1"
ENV_VARS+=",GOOGLE_CHAT_MAX_BYTES=16777216"
ENV_VARS+=",HERMES_HOME=/opt/data"
ENV_VARS+=",GOOGLE_CHAT_HTTP_EVENTS_SERVICE_ACCOUNT_EMAIL=chat@system.gserviceaccount.com"
ENV_VARS+=",API_SERVER_HOST=0.0.0.0"
if [[ -n "${GOOGLE_CHAT_ALLOWED_USERS}" ]]; then
  ENV_VARS+=",GOOGLE_CHAT_ALLOWED_USERS=${GOOGLE_CHAT_ALLOWED_USERS}"
fi
if [[ -n "${GOOGLE_CHAT_HOME_CHANNEL}" ]]; then
  ENV_VARS+=",GOOGLE_CHAT_HOME_CHANNEL=${GOOGLE_CHAT_HOME_CHANNEL}"
fi
if [[ -n "${GOOGLE_CHAT_BOOTSTRAP_SPACES}" ]]; then
  ENV_VARS+=",GOOGLE_CHAT_BOOTSTRAP_SPACES=${GOOGLE_CHAT_BOOTSTRAP_SPACES}"
fi
if [[ "${HERMES_CHAT_TRANSPORT}" == "pubsub" ]]; then
  ENV_VARS+=",GOOGLE_CHAT_SUBSCRIPTION_NAME=${GOOGLE_CHAT_SUBSCRIPTION_NAME}"
fi

DEPLOY_SECRETS=()
if [[ "${HERMES_GATEWAY_MODE}" == "embedded" ]]; then
  DEPLOY_SECRETS+=("/secrets/hermes-llm-api-key=hermes-llm-api-key:latest")
  DEPLOY_SECRETS+=("API_SERVER_KEY=hermes-api-server-key:latest")
elif [[ "${HERMES_GATEWAY_MODE}" == "proxy" ]]; then
  DEPLOY_SECRETS+=("/secrets/hermes-gateway-proxy-key=hermes-api-server-key:latest")
fi
if gcloud secrets describe "hermes-google-chat-sa-json" --project="${GCP_PROJECT}" &>/dev/null; then
  DEPLOY_SECRETS+=("/secrets/hermes-google-chat-sa-json=hermes-google-chat-sa-json:latest")
fi
SECRETS_CSV="$(IFS=,; echo "${DEPLOY_SECRETS[*]}")"

echo "==> Deploy Cloud Run ${SERVICE_NAME} (transport=${HERMES_CHAT_TRANSPORT}, mode=${HERMES_GATEWAY_MODE})"
DEPLOY_ARGS=(
  gcloud run deploy "${SERVICE_NAME}"
  --project="${GCP_PROJECT}"
  --region="${GCP_REGION}"
  --image="${IMAGE}"
  --platform=managed
  --allow-unauthenticated
  --no-invoker-iam-check
  --min-instances=1
  --max-instances=3
  --memory=512Mi
  --cpu=1
  --timeout=300
  --concurrency=10
  --port=8080
  --service-account="${SA_EMAIL}"
  --set-env-vars="${ENV_VARS}"
)
[[ -n "${SECRETS_CSV}" ]] && DEPLOY_ARGS+=(--set-secrets="${SECRETS_CSV}")
"${DEPLOY_ARGS[@]}"

URL="$(gcloud run services describe "${SERVICE_NAME}" \
  --project="${GCP_PROJECT}" \
  --region="${GCP_REGION}" \
  --format='value(status.url)')"

CHAT_HTTP_URL="${URL}${CHAT_HTTP_PATH}"

if [[ "${HERMES_CHAT_TRANSPORT}" == "http" ]]; then
  gcloud run services update "${SERVICE_NAME}" \
    --project="${GCP_PROJECT}" \
    --region="${GCP_REGION}" \
    --update-env-vars="SERVICE_URL=${URL},GOOGLE_CHAT_HTTP_EVENTS_URL=${CHAT_HTTP_URL},GOOGLE_CHAT_HTTP_EVENTS_AUDIENCE=${CHAT_HTTP_URL},API_SERVER_PORT=8080"
else
  gcloud run services update "${SERVICE_NAME}" \
    --project="${GCP_PROJECT}" \
    --region="${GCP_REGION}" \
    --update-env-vars="SERVICE_URL=${URL},GOOGLE_CHAT_SUBSCRIPTION_NAME=${GOOGLE_CHAT_SUBSCRIPTION_NAME}"
fi

mkdir -p "${ROOT}/out"
cat > "${ROOT}/out/deploy.env" <<EOF
GCP_PROJECT=${GCP_PROJECT}
GCP_REGION=${GCP_REGION}
SERVICE_URL=${URL}
CHAT_HTTP_EVENTS_URL=${CHAT_HTTP_URL}
CHAT_APP_URL=${CHAT_HTTP_URL}
HERMES_CHAT_TRANSPORT=${HERMES_CHAT_TRANSPORT}
HERMES_GATEWAY_MODE=${HERMES_GATEWAY_MODE}
GATEWAY_PROXY_URL=${GATEWAY_PROXY_URL}
GOOGLE_CHAT_SUBSCRIPTION_NAME=${GOOGLE_CHAT_SUBSCRIPTION_NAME}
CHAT_HOME_CHANNEL=${GOOGLE_CHAT_HOME_CHANNEL}
EOF
chmod 600 "${ROOT}/out/deploy.env"

echo ""
echo "Deployed: ${URL}"
if [[ "${HERMES_CHAT_TRANSPORT}" == "pubsub" ]]; then
  echo "Pub/Sub subscription (gateway vetää):"
  echo "  ${GOOGLE_CHAT_SUBSCRIPTION_NAME}"
else
  echo "Chat API HTTP endpoint (Connection settings):"
  echo "  ${CHAT_HTTP_URL}"
fi
echo "Artifact: out/deploy.env"
