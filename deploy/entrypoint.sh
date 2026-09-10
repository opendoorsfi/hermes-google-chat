#!/usr/bin/env bash
# Cloud Run entrypoint: materialize secrets, Hermes env, start gateway.
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
HERMES_CHAT_TRANSPORT="${HERMES_CHAT_TRANSPORT:-http}"
HERMES_GATEWAY_MODE="${HERMES_GATEWAY_MODE:-embedded}"
PORT="${PORT:-8080}"
mkdir -p "${HERMES_HOME}" /secrets

if [[ -f /secrets/hermes-gateway-proxy-key ]]; then
  GATEWAY_PROXY_KEY="$(tr -d '\n' < /secrets/hermes-gateway-proxy-key)"
  export GATEWAY_PROXY_KEY
elif [[ -n "${API_SERVER_KEY:-}" ]]; then
  export GATEWAY_PROXY_KEY="${API_SERVER_KEY}"
fi

# Attached SA on Cloud Run — no JSON key required.
if [[ -f /secrets/hermes-google-chat-sa-json ]]; then
  cp /secrets/hermes-google-chat-sa-json /secrets/google-chat-sa.json
  chmod 600 /secrets/google-chat-sa.json
  export GOOGLE_APPLICATION_CREDENTIALS=/secrets/google-chat-sa.json
fi

if [[ -f /secrets/hermes-api-server-key ]]; then
  API_SERVER_KEY="$(tr -d '\n' < /secrets/hermes-api-server-key)"
  export API_SERVER_KEY
fi

CHAT_HTTP_PATH="/api/platforms/google_chat/events"
if [[ -n "${SERVICE_URL:-}" ]]; then
  export GOOGLE_CHAT_HTTP_EVENTS_URL="${GOOGLE_CHAT_HTTP_EVENTS_URL:-${SERVICE_URL}${CHAT_HTTP_PATH}}"
  export GOOGLE_CHAT_HTTP_EVENTS_AUDIENCE="${GOOGLE_CHAT_HTTP_EVENTS_AUDIENCE:-${GOOGLE_CHAT_HTTP_EVENTS_URL}}"
fi
export GOOGLE_CHAT_HTTP_EVENTS_SERVICE_ACCOUNT_EMAIL="${GOOGLE_CHAT_HTTP_EVENTS_SERVICE_ACCOUNT_EMAIL:-chat@system.gserviceaccount.com}"

if [[ "${HERMES_CHAT_TRANSPORT}" == "http" ]]; then
  export API_SERVER_HOST="${API_SERVER_HOST:-0.0.0.0}"
  export API_SERVER_PORT="${API_SERVER_PORT:-${PORT}}"
  unset GOOGLE_CHAT_SUBSCRIPTION_NAME || true
fi

if [[ ! -f "${HERMES_HOME}/.env" ]]; then
  cat > "${HERMES_HOME}/.env" <<EOF
GOOGLE_CHAT_PROJECT_ID=${GOOGLE_CHAT_PROJECT_ID:-}
GOOGLE_CHAT_ALLOWED_USERS=${GOOGLE_CHAT_ALLOWED_USERS:-}
GOOGLE_CHAT_HOME_CHANNEL=${GOOGLE_CHAT_HOME_CHANNEL:-}
GOOGLE_CHAT_BOOTSTRAP_SPACES=${GOOGLE_CHAT_BOOTSTRAP_SPACES:-}
GOOGLE_CHAT_MAX_MESSAGES=${GOOGLE_CHAT_MAX_MESSAGES:-1}
GOOGLE_CHAT_MAX_BYTES=${GOOGLE_CHAT_MAX_BYTES:-16777216}
EOF
  if [[ "${HERMES_CHAT_TRANSPORT}" == "http" ]]; then
    cat >> "${HERMES_HOME}/.env" <<EOF
GOOGLE_CHAT_HTTP_EVENTS_URL=${GOOGLE_CHAT_HTTP_EVENTS_URL:-}
GOOGLE_CHAT_HTTP_EVENTS_AUDIENCE=${GOOGLE_CHAT_HTTP_EVENTS_AUDIENCE:-}
GOOGLE_CHAT_HTTP_EVENTS_SERVICE_ACCOUNT_EMAIL=${GOOGLE_CHAT_HTTP_EVENTS_SERVICE_ACCOUNT_EMAIL}
API_SERVER_HOST=${API_SERVER_HOST}
API_SERVER_PORT=${API_SERVER_PORT}
EOF
  else
    echo "GOOGLE_CHAT_SUBSCRIPTION_NAME=${GOOGLE_CHAT_SUBSCRIPTION_NAME:-}" >> "${HERMES_HOME}/.env"
  fi
fi

if [[ "${HERMES_GATEWAY_MODE}" == "proxy" ]]; then
  if [[ -z "${GATEWAY_PROXY_URL:-}" ]]; then
    echo "[entrypoint] VIRHE: HERMES_GATEWAY_MODE=proxy vaatii GATEWAY_PROXY_URL"
    exit 1
  fi
  grep -q '^GATEWAY_PROXY_URL=' "${HERMES_HOME}/.env" 2>/dev/null \
    || echo "GATEWAY_PROXY_URL=${GATEWAY_PROXY_URL}" >> "${HERMES_HOME}/.env"
  if [[ -n "${GATEWAY_PROXY_KEY:-}" ]]; then
    grep -q '^GATEWAY_PROXY_KEY=' "${HERMES_HOME}/.env" 2>/dev/null \
      || echo "GATEWAY_PROXY_KEY=${GATEWAY_PROXY_KEY}" >> "${HERMES_HOME}/.env"
  fi
  echo "[entrypoint] proxy mode → ${GATEWAY_PROXY_URL} (ei paikallista LLM:ää)"
elif [[ -f /secrets/hermes-llm-api-key ]]; then
  KEY="$(tr -d '\n' < /secrets/hermes-llm-api-key)"
  if [[ -n "${KEY}" && "${KEY}" != REPLACE_WITH_* ]]; then
    grep -q '^OPENROUTER_API_KEY=' "${HERMES_HOME}/.env" 2>/dev/null \
      || echo "OPENROUTER_API_KEY=${KEY}" >> "${HERMES_HOME}/.env"
  fi
fi

if [[ -d /opt/hermes-profiles/opendoors ]] && [[ ! -d "${HERMES_HOME}/profiles/opendoors" ]]; then
  mkdir -p "${HERMES_HOME}/profiles"
  cp -r /opt/hermes-profiles/opendoors "${HERMES_HOME}/profiles/"
fi

if [[ -f /opt/hermes-config/config.yaml.example ]] && [[ ! -f "${HERMES_HOME}/config.yaml" ]]; then
  cp /opt/hermes-config/config.yaml.example "${HERMES_HOME}/config.yaml"
fi

export HERMES_HOME

echo "[entrypoint] HERMES_HOME=${HERMES_HOME}"
echo "[entrypoint] HERMES_GATEWAY_MODE=${HERMES_GATEWAY_MODE}"
echo "[entrypoint] HERMES_CHAT_TRANSPORT=${HERMES_CHAT_TRANSPORT}"
echo "[entrypoint] GOOGLE_CHAT_PROJECT_ID=${GOOGLE_CHAT_PROJECT_ID:-unset}"
if [[ "${HERMES_CHAT_TRANSPORT}" == "http" ]]; then
  echo "[entrypoint] GOOGLE_CHAT_HTTP_EVENTS_URL=${GOOGLE_CHAT_HTTP_EVENTS_URL:-unset}"
  echo "[entrypoint] API_SERVER_PORT=${API_SERVER_PORT}"
else
  echo "[entrypoint] GOOGLE_CHAT_SUBSCRIPTION_NAME=${GOOGLE_CHAT_SUBSCRIPTION_NAME:-unset}"
fi

export PATH="/opt/hermes/bin:/opt/hermes/.venv/bin:${PATH}"
exec /opt/hermes/bin/hermes "$@"
