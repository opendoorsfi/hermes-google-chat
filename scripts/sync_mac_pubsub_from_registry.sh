#!/usr/bin/env bash
# macOS Pub/Sub gateway — yksi hermes gateway per Chat-app (agent-macbook-pro).
#
#   bash scripts/sync_mac_pubsub_from_registry.sh
#   HERMES_HOST_ID=agent-mac bash scripts/sync_mac_pubsub_from_registry.sh
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

echo "==> macOS Pub/Sub sync (host=${THIS_HOST:-?}, gateway=${GATEWAY_HOST}, primary=${PRIMARY})"

if [[ "${TRANSPORT}" != "pubsub" ]]; then
  echo "VIRHE: registry transport=${TRANSPORT} — tämä skripti on Pub/Sub:lle"
  exit 1
fi
if [[ -n "${THIS_HOST}" && "${THIS_HOST}" != "${GATEWAY_HOST}" ]]; then
  echo "OK — Pub/Sub gateway ajetaan hostilla ${GATEWAY_HOST}, ei ${THIS_HOST}"
  exit 0
fi

# Google Chat -riippuvuudet Hermeksen venvissä
HERMES_BIN="$(command -v hermes)"
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
      || "${HERMES_PY}" -m pip install --quiet google-cloud-pubsub google-api-python-client google-auth google-auth-oauthlib google-auth-httplib2 httplib2 \
      || echo "VAROITUS: riippuvuuksien asennus epäonnistui"
  fi
fi

echo "==> ${PRIMARY}: SA JSON"
export HERMES_HOME
RESTART_GATEWAY=1 bash "${ROOT}/scripts/ensure_tenant_sa.sh" "${PRIMARY}" || true

mkdir -p "${HERMES_HOME}/secrets"
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
  mkdir -p "${HERMES_HOME}"
  touch "${ENV_FILE}"
  bash "${ROOT}/scripts/print_tenant_env.sh" "${PRIMARY}" >> "${ENV_FILE}"
  echo "==> ${PRIMARY}: lisätty Chat-lohko ${ENV_FILE}"
fi
chmod 600 "${ENV_FILE}" 2>/dev/null || true

bash "${ROOT}/scripts/setup_chat_outbound_auth.sh" "${PRIMARY}" --restart 2>/dev/null || true

echo "==> Käynnistetään hermes gateway (Pub/Sub)"
if hermes gateway restart 2>/dev/null; then
  echo "OK: hermes gateway restart"
elif hermes gateway install 2>/dev/null && hermes gateway restart 2>/dev/null; then
  echo "OK: hermes gateway install + restart"
else
  echo "VAROITUS: hermes gateway restart epäonnistui — aja: hermes gateway run"
fi

for key in GOOGLE_CHAT_SUBSCRIPTION_NAME HERMES_CHAT_TRANSPORT; do
  if ! grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
    echo "VIRHE: ${key} puuttuu ${ENV_FILE}"
    exit 1
  fi
done
if [[ ! -s "${HERMES_HOME}/secrets/google-chat-sa.json" ]]; then
  echo "VAROITUS: SA JSON puuttuu — aja ensure_tenant_sa tai lataa CI-artefakti"
fi

echo "OK — macOS Pub/Sub gateway synkattu (primary=${PRIMARY})"
python3 scripts/chat_registry.py summary
