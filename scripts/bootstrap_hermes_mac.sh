#!/usr/bin/env bash
# Google Chat Hermes — macOS (ei sudo, ei Caddy). Käyttää olemassa olevaa Hermes-gatewayta.
#
#   bash scripts/bootstrap_hermes_mac.sh natalia@info.opendoors.fi
#
# Vaatii: Hermes CLI, Tailscale kirjautuneena, Funnel sallittu tailnetissä.

set -euo pipefail

EMAIL="${1:-natalia@info.opendoors.fi}"
EMAIL_LOWER="$(printf '%s' "${EMAIL}" | tr '[:upper:]' '[:lower:]')"
GCP_PROJECT="${GCP_PROJECT:-od-azuracast-sync}"
PORT="${HERMES_CHAT_PORT:-8642}"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
ENV_FILE="${HERMES_HOME}/.env"
MARKER="# --- Google Chat mac bootstrap ---"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "VIRHE: macOS-skripti — Linux-hostille: sudo bash scripts/bootstrap_hermes_host.sh"
  exit 1
fi

if ! command -v tailscale >/dev/null 2>&1; then
  echo "VIRHE: tailscale puuttuu — https://tailscale.com/download/mac"
  exit 1
fi
if ! tailscale status >/dev/null 2>&1; then
  echo "VIRHE: tailscale ei päällä — käynnistä Tailscale-app"
  exit 1
fi
if ! command -v hermes >/dev/null 2>&1; then
  echo "VIRHE: hermes puuttuu — asenna Hermes Agent"
  exit 1
fi

mkdir -p "${HERMES_HOME}/secrets"

HOSTNAME="$(tailscale status --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('Self', {}).get('DNSName', '').rstrip('.'))
" 2>/dev/null || true)"
if [[ -z "${HOSTNAME}" ]]; then
  HOSTNAME="$(tailscale status --self 2>/dev/null | awk '{print $1}' || true)"
fi
if [[ -z "${HOSTNAME}" || "${HOSTNAME}" == "100."* ]]; then
  echo "VIRHE: Tailscale-hostname ei selvinnyt — tarkista tailscale status --self"
  exit 1
fi

FUNNEL="https://${HOSTNAME}"
EVENTS_URL="${FUNNEL}/api/platforms/google_chat/events"

echo "==> macOS Google Chat bootstrap"
echo "    email:   ${EMAIL}"
echo "    funnel:  ${FUNNEL}"
echo "    port:    ${PORT}"
echo "    events:  ${EVENTS_URL}"

echo "==> Tailscale Funnel → 127.0.0.1:${PORT}"
tailscale funnel --bg "${PORT}" 2>/dev/null || tailscale funnel "${PORT}" || {
  echo "VIRHE: tailscale funnel epäonnistui — ota Funnel käyttöön tailnet/admin-asetuksissa"
  exit 1
}
tailscale funnel status 2>/dev/null || true

if [[ -f "${ENV_FILE}" ]] && grep -qF "${MARKER}" "${ENV_FILE}"; then
  echo "==> Päivitetään olemassa oleva Chat-lohko .env:ssä"
  # shellcheck disable=SC2016
  python3 - "${ENV_FILE}" "${MARKER}" <<'PY'
import pathlib, re, sys
path, marker = sys.argv[1], sys.argv[2]
text = pathlib.Path(path).read_text(encoding="utf-8")
if marker in text:
    text = text[: text.index(marker)]
    pathlib.Path(path).write_text(text.rstrip() + "\n", encoding="utf-8")
PY
fi

cat >> "${ENV_FILE}" <<EOF

${MARKER}
GOOGLE_CHAT_PROJECT_ID=${GCP_PROJECT}
GOOGLE_CHAT_ALLOWED_USERS=${EMAIL_LOWER}
GOOGLE_CHAT_MAX_MESSAGES=1
GOOGLE_CHAT_MAX_BYTES=16777216
GOOGLE_CHAT_HTTP_EVENTS_URL=${EVENTS_URL}
GOOGLE_CHAT_HTTP_EVENTS_AUDIENCE=${EVENTS_URL}
GOOGLE_CHAT_HTTP_EVENTS_SERVICE_ACCOUNT_EMAIL=chat@system.gserviceaccount.com
HERMES_CHAT_TRANSPORT=http
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=${PORT}
# GOOGLE_APPLICATION_CREDENTIALS=${HERMES_HOME}/secrets/google-chat-sa.json
# SA: hermes-chat-$(echo "${EMAIL}" | cut -d@ -f1 | tr '[:upper:]' '[:lower:]')@${GCP_PROJECT}.iam.gserviceaccount.com
# --- end Google Chat mac bootstrap ---
EOF
chmod 600 "${ENV_FILE}" 2>/dev/null || true

echo "==> Käynnistetään gateway uudelleen"
if systemctl --user is-active hermes-gateway >/dev/null 2>&1; then
  systemctl --user restart hermes-gateway
elif launchctl list 2>/dev/null | grep -qi hermes; then
  launchctl kickstart -k "gui/$(id -u)/com.hermes.gateway" 2>/dev/null || true
else
  echo "VAROITUS: hermes-gateway service ei löydy — käynnistä: hermes gateway run"
fi

sleep 2
LOCAL_CODE="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${PORT}/api/platforms/google_chat/events" \
  -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo "000")"
FUNNEL_CODE="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${EVENTS_URL}" \
  -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo "000")"

echo ""
echo "local :${PORT}  → HTTP ${LOCAL_CODE} (401/403 = OK)"
echo "funnel          → HTTP ${FUNNEL_CODE} (401/403 = OK)"
echo ""
echo "==> GCP Chat API Console (projekti ${GCP_PROJECT}):"
echo "    App name: Hermes ($(echo "${EMAIL}" | cut -d@ -f1 | sed 's/^./\U&/'))"
echo "    HTTP URL: ${EVENTS_URL}"
echo "    Visibility: ${EMAIL}"
echo ""
echo "==> Google Chat: Find apps → Hermes → Message → Hei"
if [[ ! -f "${HERMES_HOME}/secrets/google-chat-sa.json" ]]; then
  echo ""
  echo "VAROITUS: SA JSON puuttuu — luo GCP Consolesta ja tallenna:"
  echo "  ${HERMES_HOME}/secrets/google-chat-sa.json"
fi
echo ""
echo "OK — mac bootstrap valmis."
