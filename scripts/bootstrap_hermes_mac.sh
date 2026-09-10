#!/usr/bin/env bash
# Google Chat Hermes — macOS (ei sudo, ei Caddy). Käyttää olemassa olevaa Hermes-gatewayta.
#
#   bash scripts/bootstrap_hermes_mac.sh natalia@info.opendoors.fi
#
# Vaatii: Hermes CLI, Tailscale kirjautuneena, Funnel sallittu tailnetissä.

set -euo pipefail

EMAIL="${1:-natalia@info.opendoors.fi}"
EMAIL_LOWER="$(printf '%s' "${EMAIL}" | tr '[:upper:]' '[:lower:]')"
TENANT="$(python3 -c "import re; e='${EMAIL_LOWER}'.split('@')[0]; print(re.sub(r'[^a-z0-9]+','-',e.lower()).strip('-'))")"
GCP_PROJECT="${GCP_PROJECT:-od-kansiot}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"

python3 "${REPO_ROOT}/scripts/chat_registry.py" generate-all >/dev/null 2>&1 || true

PORT="${HERMES_CHAT_PORT:-$(python3 "${REPO_ROOT}/scripts/chat_registry.py" host-users natalia-mac 2>/dev/null | python3 -c "
import json, sys
users = json.load(sys.stdin)
print(users[0]['PORT'] if users else 8642)
" 2>/dev/null || echo 8642)}"
ALLOWED_ALL="$(python3 -c "
import json, pathlib
reg = json.loads(pathlib.Path('${REPO_ROOT}/config/tenants/registry.json').read_text())
emails = []
for u in reg.get('users', []):
    e = u.get('email') if isinstance(u, dict) else u
    if e:
        emails.append(str(e).strip().lower())
print(','.join(sorted(set(emails))))
" 2>/dev/null || echo "${EMAIL_LOWER}")"
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

echo "==> GCP credentials (SA JSON — outbound vaatii hermes-chat-bot-avaimen, ei käyttäjän ADC:tä)"
export TENANT
SA_CREDS=""
if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "    ADC OK (inbound/gcloud) — outbound silti tarvitsee SA JSON alla"
fi
# Outbound: org policy estää SA JSON -avaimet → ADC impersonation (ei GOOGLE_APPLICATION_CREDENTIALS)
bash "${SCRIPT_DIR}/setup_chat_outbound_auth.sh" "${TENANT}" 2>/dev/null || \
  echo "VAROITUS: outbound auth myöhemmin (setup_chat_outbound_auth) — inbound toimii ilman"
SA_CREDS=""

# API server on oletuksena pois (API_SERVER_ENABLED=false) → ilman tätä Funnel antaa 502.
API_KEY="$(grep -E '^API_SERVER_KEY=' "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- || true)"
if [[ -z "${API_KEY}" ]]; then
  API_KEY="$(openssl rand -hex 32 2>/dev/null || python3 -c 'import secrets; print(secrets.token_hex(32))')"
fi

if [[ -f "${ENV_FILE}" ]]; then
  echo "==> Poistetaan Pub/Sub-rivit .env:stä (estävät HTTP-inboundin)"
  python3 "${SCRIPT_DIR}/lib/strip_pubsub_env.py" "${ENV_FILE}" || true
fi
if [[ -f "${ENV_FILE}" ]] && grep -qF "${MARKER}" "${ENV_FILE}"; then
  echo "==> Päivitetään olemassa oleva Chat-lohko .env:ssä"
  # shellcheck disable=SC2016
  python3 - "${ENV_FILE}" "${MARKER}" <<'PY'
import pathlib, sys
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
GOOGLE_CHAT_ALLOWED_USERS=${ALLOWED_ALL}
GOOGLE_CHAT_MAX_MESSAGES=1
GOOGLE_CHAT_MAX_BYTES=16777216
GOOGLE_CHAT_HTTP_EVENTS_URL=${EVENTS_URL}
GOOGLE_CHAT_HTTP_EVENTS_AUDIENCE=${EVENTS_URL}
GOOGLE_CHAT_HTTP_EVENTS_SERVICE_ACCOUNT_EMAIL=chat@system.gserviceaccount.com
HERMES_CHAT_TRANSPORT=http
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=${PORT}
API_SERVER_KEY=${API_KEY}
${SA_CREDS}
# --- end Google Chat mac bootstrap ---
EOF
chmod 600 "${ENV_FILE}" 2>/dev/null || true

echo "==> Käynnistetään gateway uudelleen (.env päivitetty)"
bash "${SCRIPT_DIR}/ensure_mac_gateway_running.sh" "${PORT}" --restart

LOCAL_CODE="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${PORT}/api/platforms/google_chat/events" \
  -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo "000")"
FUNNEL_CODE="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${EVENTS_URL}" \
  -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo "000")"

echo ""
echo "local :${PORT}  → HTTP ${LOCAL_CODE} (401/403 = OK)"
echo "funnel          → HTTP ${FUNNEL_CODE} (401/403 = OK)"
if [[ "${FUNNEL_CODE}" == "502" || "${FUNNEL_CODE}" == "000" ]]; then
  echo "VIRHE: Funnel ei reachaa gatewayta (HTTP ${FUNNEL_CODE}) — tarkista: tailscale funnel status; hermes gateway status" >&2
  exit 1
fi
if [[ "${FUNNEL_CODE}" == "503" ]]; then
  echo "VIRHE: API server vastaa mutta Google Chat -adapter ei ole yhdistetty (503)." >&2
  echo "       Riippuvuudet: cd ~/.hermes/hermes-agent && venv/bin/python -m plugins.platforms.google_chat.oauth --install-deps" >&2
  echo "       Sitten: hermes gateway restart" >&2
  exit 1
fi
echo ""
echo "==> GCP Chat API Console (projekti ${GCP_PROJECT}):"
echo "    App name: hermes-chat"
echo "    Connection settings: HTTP endpoint URL = ${EVENTS_URL}"
echo "    Authentication audience: HTTP endpoint URL (ei Project number)"
echo "    Visibility: ${ALLOWED_ALL}"
echo ""
echo "==> Google Chat: Find apps → Hermes → Message → Hei"
if [[ ! -f "${HERMES_HOME}/secrets/google-chat-sa.json" ]]; then
  echo ""
  echo "VAROITUS: outbound-viestit vaativat SA:n — workflow/gh/gcloud hoitaa automaattisesti"
fi
echo ""
echo "OK — mac bootstrap valmis."
