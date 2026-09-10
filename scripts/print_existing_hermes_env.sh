#!/usr/bin/env bash
# Tulosta GOOGLE_CHAT_* -lohko liitettäväksi olemassa olevaan ~/.hermes/.env
#
#   bash scripts/print_existing_hermes_env.sh --transport pubsub
#   bash scripts/print_existing_hermes_env.sh --transport http --public-url https://hermes.example.com

set -euo pipefail

GCP_PROJECT="${GCP_PROJECT:-od-kansiot}"
TOPIC="${TOPIC:-hermes-chat-events}"
SUB="${SUB:-hermes-chat-events-sub}"
TRANSPORT="pubsub"
PUBLIC_URL=""
ALLOWED="${GOOGLE_CHAT_ALLOWED_USERS:-ipad@info.opendoors.fi}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --transport) TRANSPORT="$2"; shift 2 ;;
    --public-url) PUBLIC_URL="$2"; shift 2 ;;
    --allowed-users) ALLOWED="$2"; shift 2 ;;
    --project) GCP_PROJECT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--transport pubsub|http] [--public-url URL] [--allowed-users a,b]"
      exit 0
      ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

SUB_FULL="projects/${GCP_PROJECT}/subscriptions/${SUB}"

cat <<EOF
# --- Google Chat (hermes-google-chat) — liitä ~/.hermes/.env ---
GOOGLE_CHAT_PROJECT_ID=${GCP_PROJECT}
GOOGLE_CHAT_ALLOWED_USERS=${ALLOWED}
GOOGLE_CHAT_MAX_MESSAGES=1
GOOGLE_CHAT_MAX_BYTES=16777216
# GOOGLE_CHAT_HOME_CHANNEL=spaces/AAAA...
# GOOGLE_CHAT_SERVICE_ACCOUNT_JSON=/path/to/hermes-chat-bot-sa.json
EOF

if [[ "${TRANSPORT}" == "http" ]]; then
  if [[ -z "${PUBLIC_URL}" ]]; then
    echo "# VIRHE: --public-url required for http" >&2
    exit 1
  fi
  EVENTS="${PUBLIC_URL%/}/api/platforms/google_chat/events"
  cat <<EOF
GOOGLE_CHAT_HTTP_EVENTS_URL=${EVENTS}
GOOGLE_CHAT_HTTP_EVENTS_AUDIENCE=${EVENTS}
GOOGLE_CHAT_HTTP_EVENTS_SERVICE_ACCOUNT_EMAIL=chat@system.gserviceaccount.com
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
EOF
else
  cat <<EOF
GOOGLE_CHAT_SUBSCRIPTION_NAME=${SUB_FULL}
EOF
  echo "# Chat API Console → Pub/Sub → projects/${GCP_PROJECT}/topics/${TOPIC}"
fi

cat <<'EOF'
# LLM / profiilit: käytä olemassa olevia ~/.hermes-asetuksia — älä lisää uutta avainta tähän.
# --- end Google Chat block ---
EOF
