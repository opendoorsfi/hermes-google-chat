#!/usr/bin/env bash
# Korjaa Natalian Mac Chat (Funnel 502 → gateway päälle).
#
#   cd ~/hermes-google-chat && git pull && bash scripts/repair_mac_chat.sh
#   curl -fsSL https://raw.githubusercontent.com/opendoorsfi/hermes-google-chat/main/scripts/repair_mac_chat.sh | bash
set -euo pipefail

EMAIL="${1:-natalia@info.opendoors.fi}"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
REPO="${HERMES_REPO_DIR:-}"

if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/bootstrap_hermes_mac.sh" ]]; then
  REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
elif [[ -z "${REPO}" ]]; then
  for d in "${HOME}/hermes-google-chat" "${HOME}/projects/hermes-google-chat"; do
    [[ -f "${d}/scripts/repair_mac_chat.sh" ]] && REPO="${d}" && break
  done
fi
if [[ -z "${REPO}" ]]; then
  REPO="$(mktemp -d)"
  git clone --depth 1 https://github.com/opendoorsfi/hermes-google-chat.git "${REPO}"
fi

cd "${REPO}"
git pull --ff-only 2>/dev/null || true

PORT="$(python3 scripts/chat_registry.py host-users natalia-mac 2>/dev/null | python3 -c "
import json, sys
users = json.load(sys.stdin)
print(users[0]['PORT'] if users else 8642)
" 2>/dev/null || echo 8642)"

echo "==> repair_mac_chat: ${EMAIL} port ${PORT}"
TENANT="$(python3 -c "import re; e='${EMAIL}'.split('@')[0].lower(); print(re.sub(r'[^a-z0-9]+','-',e).strip('-'))")"
export TENANT
python3 scripts/lib/strip_pubsub_env.py "${HOME}/.hermes/.env" 2>/dev/null || true
bash scripts/setup_chat_outbound_auth.sh "${TENANT}" --restart || echo "VAROITUS: outbound auth (ADC impersonation) — odota Sync Chat users IAM tai gcloud auth login hostilla"
# bootstrap kirjoittaa .env:n (API_SERVER_*, GOOGLE_CHAT_HTTP_EVENTS_*) ja käynnistää gatewayn uudelleen
bash scripts/bootstrap_hermes_mac.sh "${EMAIL}" || true
bash scripts/ensure_mac_gateway_running.sh "${PORT}"

EVENTS="$(python3 scripts/chat_registry.py summary 2>/dev/null | awk -F'`' '/Chat HTTP URL/{print $2; exit}')"
FUNNEL_CODE="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${EVENTS}" \
  -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo 000)"

echo ""
echo "Funnel ${EVENTS} → HTTP ${FUNNEL_CODE}"
if [[ "${FUNNEL_CODE}" == "401" || "${FUNNEL_CODE}" == "403" ]]; then
  echo "OK — endpoint valmis (401/403)."
  bash scripts/diagnose_gchat_inbound.sh --local 2>/dev/null || true
  echo ""
  echo "Jos Chat-viesti ei vieläkään näy logissa:"
  echo "  1. Console → HTTP URL (ei Pub/Sub) → Save"
  echo "  2. Lähetä UUSI viesti Chatissa (Find apps → hermes-chat)"
  echo "  3. tail -f ~/.hermes/logs/gateway.log"
else
  echo "VIRHE: odotettiin 401/403, sain ${FUNNEL_CODE}."
  case "${FUNNEL_CODE}" in
    502|000) echo "  → Funnel ei tavoita porttia ${PORT}: tailscale funnel status; hermes gateway status" ;;
    503)     echo "  → Google Chat -adapter ei yhdistetty: riippuvuudet puuttuvat tai GOOGLE_CHAT_HTTP_EVENTS_URL puuttuu .env:stä" ;;
  esac
  hermes gateway status 2>/dev/null | sed 's/^/    /' || true
  grep -iE "GoogleChat|api.?server" "${HOME}/.hermes/logs/gateway.log" 2>/dev/null | tail -15 || true
  tail -15 "${HOME}/.hermes/logs/gateway.err" 2>/dev/null || true
  exit 1
fi
