#!/usr/bin/env bash
# GCP-resurssit + Chat Console -ohje (Pub/Sub tai HTTP).
# GitHub Actions (Sync Chat users) kutsuu tätä automaattisesti.
# Chat-appin Configuration-Save vaatii yhden Console-klikin (Google ei tarjoa julkista API:ta).
#
#   TENANT=ipad bash scripts/provision_hermes_chat_app.sh
#   HERMES_CHAT_TRANSPORT=pubsub bash scripts/provision_hermes_chat_app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/scripts/lib/tenant.sh"

HUB_JSON="$(python3 "${ROOT}/scripts/chat_registry.py" hub-json)"
TENANT="${TENANT:-$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['primary_tenant'])" "${HUB_JSON}")}"
load_tenant "${TENANT}"

TRANSPORT="${HERMES_CHAT_TRANSPORT:-$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['transport'])" "${HUB_JSON}")}"
GCP_PROJECT="${GCP_PROJECT:?}"
APP_NAME="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['chat_app_display_name'])" "${HUB_JSON}")"
ALLOWED_USERS="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['allowed_users'])" "${HUB_JSON}")"
TOPIC="${CHAT_PUBSUB_TOPIC:-$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['pubsub_topic'])" "${HUB_JSON}")}"
SUB="${CHAT_PUBSUB_SUB:-$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['pubsub_sub'])" "${HUB_JSON}")}"
TOPIC_FULL="projects/${GCP_PROJECT}/topics/${TOPIC}"
OUT_DIR="${ROOT}/out/chat-app"
mkdir -p "${OUT_DIR}"

echo "==> Hermes Chat app provision: project=${GCP_PROJECT} transport=${TRANSPORT} app=${APP_NAME}"

if [[ "${TRANSPORT}" == "pubsub" ]]; then
  export GCP_PROJECT HERMES_CHAT_TRANSPORT=pubsub TOPIC SUB
  bash "${ROOT}/infra/setup_gcp.sh"
  CONNECTION_ROWS="| Connection settings | **Cloud Pub/Sub** |
| Topic name | \`${TOPIC_FULL}\` |"
else
  INBOUND_URL="$(python3 "${ROOT}/scripts/chat_registry.py" inbound-url)"
  export CHAT_HTTP_EVENTS_URL="${CHAT_HTTP_EVENTS_URL:-${INBOUND_URL}}"
  bash "${ROOT}/infra/setup_tenant_gcp.sh"
  CONNECTION_ROWS="| Connection settings | **HTTP endpoint URL** |
| URL | \`${CHAT_HTTP_EVENTS_URL}\` |
| Authentication audience | **HTTP endpoint URL** (sama kuin URL — ei Project number) |"
fi

CONSOLE_URL="https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat?project=${GCP_PROJECT}"

cat > "${OUT_DIR}/CHAT_APP_SETUP.md" <<EOF
# Hermes Chat -app — ${APP_NAME}

> **Ei moderointi-bottia.** Moderointi on **toisessa GCP-projektissa** (\`opendoorsfi/moderate\`).
> Tämä app kuuluu projektiin **\`${GCP_PROJECT}\`**.

GitHub Actions loi Pub/Sub + SA + IAM. **Console-Save** (kerran) rekisteröi botin Chatissa.

## Console (kopioi arvot → Save)

${CONSOLE_URL}

| Kenttä | Arvo |
|--------|------|
| App status | **Live** |
| App name | **${APP_NAME}** |
| Description | Hermes Agent — Open Doors |
| Functionality | ☑ Receive 1:1 messages · ☑ Join spaces and group conversations |
${CONNECTION_ROWS}
| Visibility | **Specific people and groups** → ${ALLOWED_USERS} |

## Chatissa

1. https://chat.google.com/
2. **+** → **Find apps** → **${APP_NAME}**
3. **Message** → \`Hei\`
EOF

cp "${OUT_DIR}/CHAT_APP_SETUP.md" "${ROOT}/out/tenants/${TENANT}/CHAT_APP_SETUP.md" 2>/dev/null || \
  mkdir -p "${ROOT}/out/tenants/${TENANT}" && cp "${OUT_DIR}/CHAT_APP_SETUP.md" "${ROOT}/out/tenants/${TENANT}/CHAT_APP_SETUP.md"

echo ""
echo "OK — GCP infra + ${OUT_DIR}/CHAT_APP_SETUP.md"
echo "Console: ${CONSOLE_URL}"
cat "${OUT_DIR}/CHAT_APP_SETUP.md"
