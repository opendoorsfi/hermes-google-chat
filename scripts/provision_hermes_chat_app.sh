#!/usr/bin/env bash
# GCP-resurssit + Chat Console -ohje (Pub/Sub tai HTTP).
# Chat-appin Configuration-sivu vaatii yhden Console-Save (Google ei tarjoa API:ta).
#
#   TENANT=ipad bash scripts/provision_hermes_chat_app.sh
#   HERMES_CHAT_TRANSPORT=pubsub bash scripts/provision_hermes_chat_app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/scripts/lib/tenant.sh"

TENANT="${TENANT:-ipad}"
load_tenant "${TENANT}"

TRANSPORT="${HERMES_CHAT_TRANSPORT:-${CHAT_TRANSPORT:-pubsub}}"
GCP_PROJECT="${GCP_PROJECT:?}"
TOPIC="${CHAT_PUBSUB_TOPIC:-hermes-chat-events}"
TOPIC_FULL="projects/${GCP_PROJECT}/topics/${TOPIC}"
SUB="${CHAT_PUBSUB_SUB:-hermes-chat-events-sub}"
OUT_DIR="${ROOT}/out/tenants/${TENANT}"
mkdir -p "${OUT_DIR}"

echo "==> Hermes Chat app provision: tenant=${TENANT} project=${GCP_PROJECT} transport=${TRANSPORT}"

if [[ "${TRANSPORT}" == "pubsub" ]]; then
  export GCP_PROJECT HERMES_CHAT_TRANSPORT=pubsub TOPIC SUB
  bash "${ROOT}/infra/setup_gcp.sh"
  CONNECTION_ROWS="| Connection settings | **Cloud Pub/Sub** |
| Topic name | \`${TOPIC_FULL}\` |"
else
  bash "${ROOT}/infra/setup_tenant_gcp.sh"
  CONNECTION_ROWS="| Connection settings | **HTTP endpoint URL** |
| URL | \`${CHAT_HTTP_EVENTS_URL:-$(tenant_chat_http_url)}\` |"
fi

CONSOLE_URL="https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat?project=${GCP_PROJECT}"

cat > "${OUT_DIR}/CHAT_APP_SETUP.md" <<EOF
# Luo Hermes Chat -app (kerran) — ${CHAT_APP_DISPLAY_NAME}

> **Ei moderointi-bottia.** Moderointi on **toisessa GCP-projektissa**.
> Tämä app luodaan projektiin **\`${GCP_PROJECT}\`**.

## 1. Avaa oikea projekti

${CONSOLE_URL}

Varmista yläpalkissa: **${GCP_PROJECT}** (Open Doors AzuraCast Sync).

## 2. Configuration → täytä ja Save

| Kenttä | Arvo |
|--------|------|
| App status | **Live** (tai Testing + \`${GOOGLE_CHAT_ALLOWED_USERS}\` testaajana) |
| App name | **${CHAT_APP_DISPLAY_NAME}** |
| Description | Hermes Agent — ${TENANT} |
| Functionality | ☑ Receive 1:1 messages · ☑ Join spaces and group conversations |
${CONNECTION_ROWS}
| Visibility | **Specific people and groups** → \`${GOOGLE_CHAT_ALLOWED_USERS}\` |

**Save**

## 3. Chatissa (ipad@)

1. https://chat.google.com/
2. **+** → **Find apps** → hae **${CHAT_APP_DISPLAY_NAME}**
3. **Message** → \`Hei\`

## 4. Gateway

Hermes hostilla \`GOOGLE_CHAT_ALLOWED_USERS\` sisältää \`${GOOGLE_CHAT_ALLOWED_USERS}\`.
Pub/Sub: subscription \`${SUB}\` → gateway Connected.

---
GitHub Actions loi GCP-infra (SA, topic, IAM). Console-Save on ainoa manuaalinen askel.
EOF

echo ""
echo "OK — GCP infra + ${OUT_DIR}/CHAT_APP_SETUP.md"
echo "Console (kopioi arvot): ${CONSOLE_URL}"
cat "${OUT_DIR}/CHAT_APP_SETUP.md"
