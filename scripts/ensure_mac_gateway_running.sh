#!/usr/bin/env bash
# Varmista että hermes gateway kuuntelee paikallista porttia (macOS).
#   bash scripts/ensure_mac_gateway_running.sh [PORT]
set -euo pipefail

PORT="${1:-8642}"
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

CODE="$(local_code)"
if [[ "${CODE}" == "401" || "${CODE}" == "403" ]]; then
  echo "OK: gateway jo kuuntelee :${PORT} (HTTP ${CODE})"
  exit 0
fi

echo "==> Gateway ei vastaa :${PORT} (HTTP ${CODE}) — käynnistetään"

mkdir -p "${HERMES_HOME}/logs" "${HOME}/Library/LaunchAgents"

if [[ -f "${PLIST_SRC}" ]]; then
  sed -e "s|__HERMES_BIN__|${HERMES_BIN}|g" \
      -e "s|__HERMES_HOME__|${HERMES_HOME}|g" \
      "${PLIST_SRC}" > "${PLIST_DST}"
  launchctl bootout "gui/${UID_NUM}" "${PLIST_DST}" 2>/dev/null || true
  launchctl bootstrap "gui/${UID_NUM}" "${PLIST_DST}"
  launchctl enable "gui/${UID_NUM}/com.hermes.gateway" 2>/dev/null || true
  launchctl kickstart -k "gui/${UID_NUM}/com.hermes.gateway" 2>/dev/null || true
else
  echo "VAROITUS: plist puuttuu — nohup fallback"
  pkill -f "hermes gateway run" 2>/dev/null || true
  nohup env HERMES_HOME="${HERMES_HOME}" "${HERMES_BIN}" gateway run \
    >> "${HERMES_HOME}/logs/gateway.log" 2>> "${HERMES_HOME}/logs/gateway.err" &
fi

for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 2
  CODE="$(local_code)"
  if [[ "${CODE}" == "401" || "${CODE}" == "403" ]]; then
    echo "OK: gateway kuuntelee :${PORT} (HTTP ${CODE})"
    exit 0
  fi
  echo "   odottaa gateway… HTTP ${CODE}"
done

echo "VIRHE: gateway ei vastaa :${PORT} — tarkista ${HERMES_HOME}/logs/gateway.err" >&2
tail -20 "${HERMES_HOME}/logs/gateway.err" 2>/dev/null || true
exit 1
