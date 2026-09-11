#!/usr/bin/env bash
# macOS Pub/Sub gateway — agent-macbook-pro (yksi hermes gateway per Chat-app).
#
#   bash scripts/sync_mac_pubsub_from_registry.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "VIRHE: vain macOS — Linux: sudo bash scripts/sync_host_from_registry.sh"
  exit 1
fi
if ! command -v hermes >/dev/null 2>&1; then
  echo "VIRHE: hermes CLI puuttuu"
  exit 1
fi

python3 scripts/chat_registry.py generate-all

TRANSPORT="$(python3 -c "import json; print(json.load(open('config/tenants/registry.json'))['default_chat_transport'])")"
GATEWAY_HOST="$(python3 scripts/chat_registry.py hub-json | python3 -c "import json,sys; print(json.load(sys.stdin)['chat_gateway_host'])")"
THIS_HOST="${HERMES_HOST_ID:-$(python3 scripts/chat_registry.py local-host-id 2>/dev/null || true)}"
PRIMARY="$(python3 scripts/chat_registry.py hub-json | python3 -c "import json,sys; print(json.load(sys.stdin)['primary_tenant'])")"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
ENV_FILE="${HERMES_HOME}/.env"
HERMES_BIN="$(command -v hermes)"

echo "==> macOS Pub/Sub sync (host=${THIS_HOST:-?}, gateway=${GATEWAY_HOST}, primary=${PRIMARY})"

if [[ "${TRANSPORT}" != "pubsub" ]]; then
  echo "VIRHE: registry transport=${TRANSPORT}"
  exit 1
fi
if [[ -n "${THIS_HOST}" && "${THIS_HOST}" != "${GATEWAY_HOST}" ]]; then
  echo "OK — gateway host=${GATEWAY_HOST}, tämä=${THIS_HOST}"
  exit 0
fi

# Google Chat -riippuvuudet
HERMES_PY=""
for cand in "${HERMES_HOME}/hermes-agent/venv/bin/python" /usr/local/lib/hermes-agent/venv/bin/python; do
  [[ -n "${cand}" && -x "${cand}" ]] && HERMES_PY="${cand}" && break
done
if [[ -z "${HERMES_PY}" ]]; then
  HERMES_PY="$(grep -oE '[^ "'"'"']+/venv/bin/python[0-9.]*' "${HERMES_BIN}" 2>/dev/null | head -1 || true)"
fi
if [[ -n "${HERMES_PY}" && -x "${HERMES_PY}" ]]; then
  if ! "${HERMES_PY}" -c "import google.cloud.pubsub_v1, googleapiclient.discovery, google_auth_httplib2" >/dev/null 2>&1; then
    echo "==> Asennetaan Google Chat -riippuvuudet"
    HERMES_SRC="${HERMES_PY%/venv/bin/python*}"
    (cd "${HERMES_SRC}" && "${HERMES_PY}" -m plugins.platforms.google_chat.oauth --install-deps) \
      || "${HERMES_PY}" -m pip install --quiet google-cloud-pubsub google-api-python-client google-auth google-auth-oauthlib google-auth-httplib2 httplib2
  fi
fi

mkdir -p "${HERMES_HOME}/logs" "${HERMES_HOME}/secrets"
export HERMES_HOME

MARKER="# --- Google Chat tenant ${PRIMARY} (generated"
if [[ -f "${ENV_FILE}" ]] && grep -qF "${MARKER}" "${ENV_FILE}" 2>/dev/null; then
  echo "==> ${PRIMARY}: päivitetään Chat-lohko"
  NEW_BLOCK="$(mktemp)"
  bash "${ROOT}/scripts/print_tenant_env.sh" "${PRIMARY}" > "${NEW_BLOCK}"
  python3 - "${ENV_FILE}" "${NEW_BLOCK}" <<'PY'
import pathlib, re, sys
env_path, block_path = sys.argv[1], sys.argv[2]
new_block = pathlib.Path(block_path).read_text(encoding="utf-8")
text = pathlib.Path(env_path).read_text(encoding="utf-8")
pattern = r"# --- Google Chat tenant .*?--- end Google Chat tenant .*? ---\n?"
if re.search(pattern, text, flags=re.S):
    text = re.sub(pattern, new_block, text, count=1, flags=re.S)
else:
    text = text.rstrip() + "\n\n" + new_block
pathlib.Path(env_path).write_text(text, encoding="utf-8")
PY
  rm -f "${NEW_BLOCK}"
else
  touch "${ENV_FILE}"
  bash "${ROOT}/scripts/print_tenant_env.sh" "${PRIMARY}" >> "${ENV_FILE}"
fi
chmod 600 "${ENV_FILE}" 2>/dev/null || true

echo "==> Pub/Sub auth (EI setup_chat_outbound_auth — se poistaa inbound-credentiaalit)"
bash "${ROOT}/scripts/setup_chat_pubsub_auth.sh" "${PRIMARY}"

# Päivitä launchd wrapper (impersonation + .env)
PLIST_DST="${HOME}/Library/LaunchAgents/com.hermes.gateway.plist"
WRAPPER="${ROOT}/scripts/hermes_gateway_run.sh"
chmod +x "${WRAPPER}"
if [[ -f "${PLIST_DST}" ]]; then
  launchctl bootout "gui/$(id -u)" "${PLIST_DST}" 2>/dev/null || true
fi
mkdir -p "${HOME}/Library/LaunchAgents"
sed -e "s|__HERMES_BIN__|${WRAPPER}|g" \
    -e "s|__HERMES_HOME__|${HERMES_HOME}|g" \
    "${ROOT}/deploy/macos/com.hermes.gateway.plist" > "${PLIST_DST}"
launchctl bootstrap "gui/$(id -u)" "${PLIST_DST}" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/com.hermes.gateway" 2>/dev/null || true

echo "==> Käynnistetään hermes gateway (Pub/Sub)"
export HERMES_BIN
if [[ -f "${ENV_FILE}" ]]; then
  IMP_SA="$(grep '^GOOGLE_CHAT_IMPERSONATE_SERVICE_ACCOUNT=' "${ENV_FILE}" 2>/dev/null | cut -d= -f2- || true)"
  [[ -n "${IMP_SA}" ]] && export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="${IMP_SA}"
fi
HERMES_HOME="${HERMES_HOME}" "${HERMES_BIN}" gateway restart 2>/dev/null \
  || HERMES_HOME="${HERMES_HOME}" "${WRAPPER}" &

sleep 6
bash "${ROOT}/scripts/verify_pubsub_gateway.sh" || {
  echo ""
  echo "=== gateway.err (viimeiset) ==="
  tail -30 "${HERMES_HOME}/logs/gateway.err" 2>/dev/null || true
  exit 1
}

echo "OK — macOS Pub/Sub gateway synkattu"
python3 scripts/chat_registry.py summary
