#!/usr/bin/env bash
# Varmista että hermes gateway + API server kuuntelee paikallista porttia (macOS).
#   bash scripts/ensure_mac_gateway_running.sh [PORT] [--restart]
#
# --restart: käynnistä gateway uudelleen vaikka portti vastaisi (esim. .env muuttui).
#
# Vaatimukset joita tämä tarkistaa/korjaa:
#   1. Google Chat -riippuvuudet Hermeksen venvissä (google-cloud-pubsub ym. eivät kuulu
#      oletusasennukseen → ilman niitä API server vastaa 503 "adapter is not connected").
#   2. Gateway ajossa Hermeksen omana launchd-palveluna (hermes gateway install/restart).
#   3. POST /api/platforms/google_chat/events ilman tokenia → 401 (= API server + adapter OK).
set -euo pipefail

PORT="${1:-8642}"
FORCE_RESTART=0
[[ "${2:-}" == "--restart" ]] && FORCE_RESTART=1
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
HERMES_BIN="$(command -v hermes || true)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_DST="${HOME}/Library/LaunchAgents/com.hermes.gateway.plist"
PLIST_SRC="${ROOT}/deploy/macos/com.hermes.gateway.plist"
UID_NUM="$(id -u)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "VIRHE: vain macOS"
  exit 1
fi
if [[ -z "${HERMES_BIN}" ]]; then
  echo "VIRHE: hermes CLI puuttuu"
  exit 1
fi

local_code() {
  curl -sS -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${PORT}/api/platforms/google_chat/events" \
    -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo "000"
}

explain_code() {
  case "$1" in
    401|403) echo "OK: gateway + Google Chat adapter kuuntelee :${PORT} (HTTP $1)" ;;
    503) echo "API server vastaa mutta Google Chat -adapter ei ole yhdistetty (HTTP 503) — riippuvuudet tai GOOGLE_CHAT_HTTP_EVENTS_URL puuttuu" ;;
    000) echo "portti :${PORT} ei vastaa — API_SERVER_ENABLED=true + API_SERVER_KEY puuttuu tai gateway ei käy" ;;
    *)   echo "odottamaton HTTP $1 portista :${PORT}" ;;
  esac
}

# --- 1. Hermes venv python + Google Chat -riippuvuudet -----------------------
HERMES_SRC="${HERMES_INSTALL_DIR:-${HERMES_HOME}/hermes-agent}"
HERMES_PY=""
for cand in "${HERMES_SRC}/venv/bin/python" "${HERMES_SRC}/.venv/bin/python"; do
  [[ -x "${cand}" ]] && HERMES_PY="${cand}" && break
done
if [[ -z "${HERMES_PY}" ]]; then
  # hermes-wrapperi viittaa venvin pythoniin
  HERMES_PY="$(grep -oE '[^ "'"'"']+/venv/bin/python[0-9.]*' "${HERMES_BIN}" 2>/dev/null | head -1 || true)"
  [[ -n "${HERMES_PY}" && -x "${HERMES_PY}" ]] && HERMES_SRC="${HERMES_PY%/venv/bin/python*}"
fi

if [[ -n "${HERMES_PY}" && -x "${HERMES_PY}" ]]; then
  if ! "${HERMES_PY}" -c "import google.cloud.pubsub_v1, google.oauth2.service_account, google_auth_httplib2, googleapiclient.discovery, httplib2" >/dev/null 2>&1; then
    echo "==> Asennetaan Google Chat -riippuvuudet Hermeksen venviin"
    if [[ -d "${HERMES_SRC}/plugins/platforms/google_chat" ]]; then
      (cd "${HERMES_SRC}" && "${HERMES_PY}" -m plugins.platforms.google_chat.oauth --install-deps) || true
    fi
    if ! "${HERMES_PY}" -c "import google.cloud.pubsub_v1, googleapiclient.discovery, google_auth_httplib2" >/dev/null 2>&1; then
      PKGS="google-cloud-pubsub google-api-python-client google-auth google-auth-oauthlib google-auth-httplib2 httplib2"
      if command -v uv >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        uv pip install --python "${HERMES_PY}" ${PKGS} || true
      else
        # shellcheck disable=SC2086
        "${HERMES_PY}" -m pip install --quiet ${PKGS} || true
      fi
    fi
    if "${HERMES_PY}" -c "import google.cloud.pubsub_v1, googleapiclient.discovery, google_auth_httplib2" >/dev/null 2>&1; then
      echo "    riippuvuudet OK"
      FORCE_RESTART=1
    else
      echo "VAROITUS: Google Chat -riippuvuuksien asennus epäonnistui — aja käsin:"
      echo "    cd ${HERMES_SRC} && ${HERMES_PY} -m plugins.platforms.google_chat.oauth --install-deps"
    fi
  fi
else
  echo "VAROITUS: Hermeksen venv-pythonia ei löytynyt (${HERMES_SRC}) — riippuvuustarkistus ohitettu"
fi

# --- 2. Tarvitseeko käynnistää? ---------------------------------------------
CODE="$(local_code)"
if [[ "${FORCE_RESTART}" == "0" && ( "${CODE}" == "401" || "${CODE}" == "403" ) ]]; then
  explain_code "${CODE}"
  exit 0
fi
echo "==> $(explain_code "${CODE}") — käynnistetään gateway uudelleen"
mkdir -p "${HERMES_HOME}/logs"

# Vanha oma plist (aiempi versio tästä skriptistä) pois, jotta ei ole kahta valvojaa.
if [[ -f "${PLIST_DST}" ]]; then
  launchctl bootout "gui/${UID_NUM}" "${PLIST_DST}" 2>/dev/null || true
  rm -f "${PLIST_DST}"
fi

# --- 3. Hermeksen oma launchd-palvelu ----------------------------------------
NATIVE_OK=0
if HERMES_HOME="${HERMES_HOME}" "${HERMES_BIN}" gateway install >/dev/null 2>&1 \
   || HERMES_HOME="${HERMES_HOME}" "${HERMES_BIN}" gateway install --force >/dev/null 2>&1; then
  NATIVE_OK=1
fi
if [[ "${NATIVE_OK}" == "1" ]]; then
  # restart hoitaa myös käsin käynnistetyn (terminaali) gatewayn: SIGUSR1 → uudelleenkäynnistys uudella .env:llä
  HERMES_HOME="${HERMES_HOME}" "${HERMES_BIN}" gateway restart 2>&1 | sed 's/^/    /' || \
    HERMES_HOME="${HERMES_HOME}" "${HERMES_BIN}" gateway start 2>&1 | sed 's/^/    /' || true
else
  echo "VAROITUS: hermes gateway install epäonnistui — fallback omaan launchd-plistiin"
  pkill -f "hermes_cli.main.* gateway run" 2>/dev/null || true
  pkill -f "hermes gateway run" 2>/dev/null || true
  sleep 1
  if [[ -f "${PLIST_SRC}" ]]; then
    mkdir -p "${HOME}/Library/LaunchAgents"
    sed -e "s|__HERMES_BIN__|${HERMES_BIN}|g" \
        -e "s|__HERMES_HOME__|${HERMES_HOME}|g" \
        "${PLIST_SRC}" > "${PLIST_DST}"
    launchctl bootstrap "gui/${UID_NUM}" "${PLIST_DST}"
    launchctl enable "gui/${UID_NUM}/com.hermes.gateway" 2>/dev/null || true
    launchctl kickstart -k "gui/${UID_NUM}/com.hermes.gateway" 2>/dev/null || true
  else
    nohup env HERMES_HOME="${HERMES_HOME}" "${HERMES_BIN}" gateway run \
      >> "${HERMES_HOME}/logs/gateway.log" 2>> "${HERMES_HOME}/logs/gateway.err" &
  fi
fi

# --- 4. Odota että portti vastaa --------------------------------------------
for _ in $(seq 1 20); do
  sleep 3
  CODE="$(local_code)"
  if [[ "${CODE}" == "401" || "${CODE}" == "403" ]]; then
    explain_code "${CODE}"
    exit 0
  fi
  echo "   odottaa gateway… HTTP ${CODE}"
done

echo "VIRHE: $(explain_code "${CODE}")" >&2
echo "--- hermes gateway status ---" >&2
HERMES_HOME="${HERMES_HOME}" "${HERMES_BIN}" gateway status 2>&1 | sed 's/^/    /' >&2 || true
echo "--- gateway.log (GoogleChat / api_server) ---" >&2
{ grep -iE "GoogleChat|api.?server|API_SERVER|Traceback|Error" "${HERMES_HOME}/logs/gateway.log" 2>/dev/null | tail -20; } >&2 || true
tail -20 "${HERMES_HOME}/logs/gateway.err" 2>/dev/null >&2 || true
exit 1
