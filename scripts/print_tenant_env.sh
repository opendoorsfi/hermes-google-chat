#!/usr/bin/env bash
# Print GOOGLE_CHAT block for tenant's ~/.hermes/.env (HTTP + Funnel path).
#
#   bash scripts/print_tenant_env.sh alice
#   sudo -u hermes-alice bash scripts/print_tenant_env.sh alice >> ~hermes-alice/.hermes/.env

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/scripts/lib/tenant.sh"

TENANT="${1:?Usage: print_tenant_env.sh TENANT}"
load_tenant "${TENANT}"

EVENTS_URL="$(tenant_chat_http_url)"
API_PORT="${PORT:?PORT missing in tenant config}"

cat <<EOF
# --- Google Chat tenant ${TENANT} (generated) ---
GOOGLE_CHAT_PROJECT_ID=${GCP_PROJECT}
GOOGLE_CHAT_ALLOWED_USERS=${GOOGLE_CHAT_ALLOWED_USERS}
GOOGLE_CHAT_MAX_MESSAGES=1
GOOGLE_CHAT_MAX_BYTES=16777216
GOOGLE_CHAT_HTTP_EVENTS_URL=${EVENTS_URL}
GOOGLE_CHAT_HTTP_EVENTS_AUDIENCE=${EVENTS_URL}
GOOGLE_CHAT_HTTP_EVENTS_SERVICE_ACCOUNT_EMAIL=chat@system.gserviceaccount.com
HERMES_CHAT_TRANSPORT=http
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=${API_PORT}
# GOOGLE_CHAT_SERVICE_ACCOUNT_JSON=/home/${LINUX_USER}/.hermes/secrets/google-chat-sa.json
# Optional: agent on another tailnet host
# GATEWAY_PROXY_URL=http://100.x.y.z:8642
# GATEWAY_PROXY_KEY=
# LLM keys: existing ~/.hermes/.env — do not duplicate here
# --- end Google Chat tenant ${TENANT} ---
EOF
