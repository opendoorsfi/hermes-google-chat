#!/usr/bin/env bash
# Print GOOGLE_CHAT block for tenant's ~/.hermes/.env (Pub/Sub per Hermes docs Step 9).
#
#   bash scripts/print_tenant_env.sh ipad
#   sudo -u hermes-ipad bash scripts/print_tenant_env.sh ipad >> ~hermes-ipad/.hermes/.env

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/scripts/lib/tenant.sh"

TENANT="${1:?Usage: print_tenant_env.sh TENANT}"
load_tenant "${TENANT}"

TRANSPORT="${CHAT_TRANSPORT:-pubsub}"
ALLOWED="${GOOGLE_CHAT_ALLOWED_USERS}"
if [[ "${TRANSPORT}" == "pubsub" ]]; then
  ALLOWED="$(python3 "${ROOT}/scripts/chat_registry.py" hub-json | python3 -c "import json,sys; print(json.load(sys.stdin)['allowed_users'])")"
  SUB_FULL="projects/${GCP_PROJECT}/subscriptions/${CHAT_PUBSUB_SUB}"
  SA_JSON="/home/${LINUX_USER}/.hermes/secrets/google-chat-sa.json"
  cat <<EOF
# --- Google Chat tenant ${TENANT} (generated, Pub/Sub) ---
GOOGLE_CHAT_PROJECT_ID=${GCP_PROJECT}
GOOGLE_CHAT_SUBSCRIPTION_NAME=${SUB_FULL}
GOOGLE_CHAT_SERVICE_ACCOUNT_JSON=${SA_JSON}
GOOGLE_CHAT_ALLOWED_USERS=${ALLOWED}
GOOGLE_CHAT_MAX_MESSAGES=1
GOOGLE_CHAT_MAX_BYTES=16777216
HERMES_CHAT_TRANSPORT=pubsub
# LLM keys: existing ~/.hermes/.env — do not duplicate here
# --- end Google Chat tenant ${TENANT} ---
EOF
else
  EVENTS_URL="$(tenant_chat_http_url)"
  API_PORT="${PORT:?PORT missing in tenant config}"
  cat <<EOF
# --- Google Chat tenant ${TENANT} (generated, HTTP) ---
GOOGLE_CHAT_PROJECT_ID=${GCP_PROJECT}
GOOGLE_CHAT_ALLOWED_USERS=${ALLOWED}
GOOGLE_CHAT_MAX_MESSAGES=1
GOOGLE_CHAT_MAX_BYTES=16777216
GOOGLE_CHAT_HTTP_EVENTS_URL=${EVENTS_URL}
GOOGLE_CHAT_HTTP_EVENTS_AUDIENCE=${EVENTS_URL}
GOOGLE_CHAT_HTTP_EVENTS_SERVICE_ACCOUNT_EMAIL=chat@system.gserviceaccount.com
HERMES_CHAT_TRANSPORT=http
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=${API_PORT}
API_SERVER_KEY=${API_SERVER_KEY:-$(openssl rand -hex 32 2>/dev/null || python3 -c 'import secrets; print(secrets.token_hex(32))')}
# GOOGLE_CHAT_SERVICE_ACCOUNT_JSON=/home/${LINUX_USER}/.hermes/secrets/google-chat-sa.json
# --- end Google Chat tenant ${TENANT} ---
EOF
fi
