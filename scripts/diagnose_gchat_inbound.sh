#!/usr/bin/env bash
# Diagnostiikka: miksi Google Chat -inbound ei näy logissa.
#   bash scripts/diagnose_gchat_inbound.sh          # etäsmoke (funnel)
#   bash scripts/diagnose_gchat_inbound.sh --local    # Mac/Linux host (luku .env + gateway)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INBOUND="$(python3 "${ROOT}/scripts/chat_registry.py" inbound-url)"
LOCAL=0
[[ "${1:-}" == "--local" ]] && LOCAL=1

echo "=== Google Chat inbound diagnostiikka ==="
echo "Registry inbound URL: ${INBOUND}"
echo ""

echo "--- 1. Funnel smoke (ei tokenia → 401 missing_google_bearer) ---"
BODY="$(curl -sS -X POST "${INBOUND}" -H 'Content-Type: application/json' -d '{}' --max-time 20 -w '\n__HTTP__%{http_code}__' 2>/dev/null || echo '__HTTP__000__')"
HTTP="${BODY##*__HTTP__}"
HTTP="${HTTP%%__*}"
RESP="${BODY%__HTTP__*}"
echo "HTTP ${HTTP}"
echo "${RESP}" | head -c 300
echo ""

echo "--- 2. Authorization header läpi Funnelin ---"
CODE_BEARER="$(curl -sS -o /tmp/gchat_bearer.json -w '%{http_code}' -X POST "${INBOUND}" \
  -H 'Content-Type: application/json' -H 'Authorization: Bearer test' -d '{}' --max-time 20 2>/dev/null || echo 000)"
echo "fake Bearer → HTTP ${CODE_BEARER} ($(python3 -c "import json; print(json.load(open('/tmp/gchat_bearer.json')).get('error',{}).get('code','?'))" 2>/dev/null || echo '?'))"
if [[ "${CODE_BEARER}" == "401" ]] && grep -q invalid_google_bearer /tmp/gchat_bearer.json 2>/dev/null; then
  echo "OK: Authorization-header tulee perille (ei missing_google_bearer)"
else
  echo "VAROITUS: Bearer-testi epäselvä — tarkista Funnel"
fi
echo ""

if [[ "${LOCAL}" != "1" ]]; then
  echo "--- 3. Host-tarkistus (aja Macilla: bash scripts/diagnose_gchat_inbound.sh --local) ---"
  echo "  cd ~/hermes-google-chat && git pull && bash scripts/repair_mac_chat.sh natalia@info.opendoors.fi"
  exit 0
fi

ENV_FILE="${HERMES_HOME:-${HOME}/.hermes}/.env"
echo "--- 3. ~/.hermes/.env (kriittiset rivit) ---"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "VIRHE: ${ENV_FILE} puuttuu"
  exit 1
fi
grep -E '^(GOOGLE_CHAT_SUBSCRIPTION|GOOGLE_CHAT_HTTP_EVENTS|GOOGLE_CHAT_ALLOWED|API_SERVER_|GOOGLE_CHAT_SERVICE_ACCOUNT)' "${ENV_FILE}" 2>/dev/null || true
if grep -qE '^GOOGLE_CHAT_SUBSCRIPTION(_NAME)?=' "${ENV_FILE}" 2>/dev/null; then
  echo ""
  echo "VIRHE: GOOGLE_CHAT_SUBSCRIPTION_* estää HTTP-inboundin!"
  echo "  Korjaus: python3 scripts/lib/strip_pubsub_env.py ${ENV_FILE}"
  echo "  Sitten: hermes gateway restart"
  exit 1
fi

AUD="$(grep -E '^GOOGLE_CHAT_HTTP_EVENTS_AUDIENCE=' "${ENV_FILE}" | head -1 | cut -d= -f2- || true)"
URL="$(grep -E '^GOOGLE_CHAT_HTTP_EVENTS_URL=' "${ENV_FILE}" | head -1 | cut -d= -f2- || true)"
if [[ -n "${AUD}" && "${AUD}" != "${INBOUND}" && "${AUD}" != "${URL}" ]]; then
  echo "VAROITUS: AUDIENCE (${AUD}) ≠ registry inbound (${INBOUND})"
fi
if [[ -n "${URL}" && "${URL}" != "${INBOUND}" ]]; then
  echo "VAROITUS: HTTP_EVENTS_URL (${URL}) ≠ registry (${INBOUND})"
fi

PORT="$(python3 "${ROOT}/scripts/chat_registry.py" host-users natalia-mac 2>/dev/null | python3 -c "import json,sys; u=json.load(sys.stdin); print(u[0]['PORT'])" 2>/dev/null || echo 8642)"
echo ""
echo "--- 4. Paikallinen gateway :${PORT} ---"
LCODE="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${PORT}/api/platforms/google_chat/events" \
  -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo 000)"
echo "local → HTTP ${LCODE}"

echo ""
echo "--- 5. Gateway / GoogleChat logit (viimeiset) ---"
for f in "${HERMES_HOME:-${HOME}/.hermes}/logs/gateway.log" "${HERMES_HOME:-${HOME}/.hermes}/logs/gateway.err"; do
  [[ -f "${f}" ]] && { echo "== ${f} =="; grep -iE 'GoogleChat|google_chat|api.?server|subscription|http' "${f}" 2>/dev/null | tail -8 || echo "(ei rivejä)"; }
done

echo ""
echo "--- 6. Console (manuaalinen) ---"
bash "${ROOT}/scripts/print_console_save.sh" | head -20
echo ""
echo "Jos funnel=401 mutta Chat-viesti ei näy logissa:"
echo "  • Console yhä Pub/Sub TAI .env:ssä GOOGLE_CHAT_SUBSCRIPTION_* rivi"
echo "  • Pub/Sub→HTTP Console-muutos poisti botin vanhasta DM:stä → Find apps → hermes-chat → UUSI keskustelu → Hei"
