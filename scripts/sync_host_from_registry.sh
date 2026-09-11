#!/usr/bin/env bash
# Apply all registry tenants on Hermes host (self-hosted runner or SSH).
# Pub/Sub: vain gateway-host ajaa hermes gateway (yksi subscription per Chat-app).
#
#   sudo bash scripts/sync_host_from_registry.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "VIRHE: aja rootina (sudo) — systemd + useradd"
  exit 1
fi

python3 scripts/chat_registry.py generate-all

TRANSPORT="$(python3 -c "import json; print(json.load(open('config/tenants/registry.json'))['default_chat_transport'])")"
GATEWAY_HOST="$(python3 -c "
import json, sys
sys.path.insert(0, 'scripts')
from chat_registry import gateway_host_id, load_registry
print(gateway_host_id(load_registry()))
")"
THIS_HOST="${HERMES_HOST_ID:-work-h}"

mapfile -t TENANTS < <(python3 scripts/chat_registry.py list-ids)
if [[ ${#TENANTS[@]} -eq 0 ]]; then
  echo "VAROITUS: registry tyhjä"
  exit 0
fi

ARGS=()
for t in "${TENANTS[@]}"; do
  ARGS+=(--tenant "$t")
done
bash "${ROOT}/scripts/install_hermes_host.sh" "${ARGS[@]}"

# Google Chat -riippuvuudet (google-cloud-pubsub ym.) eivät kuulu Hermeksen oletusasennukseen.
HERMES_BIN="$(command -v hermes || echo /usr/local/bin/hermes)"
HERMES_PY=""
for cand in /usr/local/lib/hermes-agent/venv/bin/python "${HOME}/.hermes/hermes-agent/venv/bin/python" \
            "$(grep -oE '[^ "'"'"']+/venv/bin/python[0-9.]*' "${HERMES_BIN}" 2>/dev/null | head -1 || true)"; do
  [[ -n "${cand}" && -x "${cand}" ]] && HERMES_PY="${cand}" && break
done
if [[ -n "${HERMES_PY}" ]]; then
  HERMES_SRC="${HERMES_PY%/venv/bin/python*}"
  if ! "${HERMES_PY}" -c "import google.cloud.pubsub_v1, googleapiclient.discovery, google_auth_httplib2" >/dev/null 2>&1; then
    echo "==> Asennetaan Google Chat -riippuvuudet (${HERMES_SRC})"
    (cd "${HERMES_SRC}" && "${HERMES_PY}" -m plugins.platforms.google_chat.oauth --install-deps) \
      || "${HERMES_PY}" -m pip install --quiet google-cloud-pubsub google-api-python-client google-auth google-auth-oauthlib google-auth-httplib2 httplib2 \
      || echo "VAROITUS: riippuvuuksien asennus epäonnistui — aja käsin: cd ${HERMES_SRC} && venv/bin/python -m plugins.platforms.google_chat.oauth --install-deps"
  fi
else
  echo "VAROITUS: Hermeksen venviä ei löytynyt — Google Chat -riippuvuuksia ei tarkistettu"
fi

if [[ "${TRANSPORT}" == "pubsub" && "${THIS_HOST}" != "${GATEWAY_HOST}" ]]; then
  echo "OK — Pub/Sub gateway ajetaan hostilla ${GATEWAY_HOST}, ei ${THIS_HOST}"
  exit 0
fi

PRIMARY="$(python3 scripts/chat_registry.py hub-json | python3 -c "import json,sys; print(json.load(sys.stdin)['primary_tenant'])")"

for t in "${TENANTS[@]}"; do
  # shellcheck source=scripts/lib/tenant.sh
  source "${ROOT}/scripts/lib/tenant.sh"
  load_tenant "${t}"
  if [[ "${TRANSPORT}" == "pubsub" && "${t}" != "${PRIMARY}" ]]; then
    echo "==> ${t}: ohitetaan gateway (Pub/Sub primary=${PRIMARY})"
    continue
  fi

  echo "==> ${t}: SA JSON"
  bash "${ROOT}/scripts/ensure_tenant_sa.sh" "${t}" || true
  load_tenant "${t}"
  ENV_FILE="/home/${LINUX_USER}/.hermes/.env"
  MARKER="# --- Google Chat tenant ${t} (generated"
  if [[ -f "${ENV_FILE}" ]] && grep -qF "${MARKER}" "${ENV_FILE}" 2>/dev/null; then
    echo "==> ${t}: päivitetään Chat-lohko"
    NEW_BLOCK="$(mktemp)"
    bash "${ROOT}/scripts/print_tenant_env.sh" "${t}" > "${NEW_BLOCK}"
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
    mkdir -p "/home/${LINUX_USER}/.hermes"
    touch "${ENV_FILE}"
    bash "${ROOT}/scripts/print_tenant_env.sh" "${t}" >> "${ENV_FILE}"
    echo "==> ${t}: appended Chat block to ${ENV_FILE}"
  fi
  chown "${LINUX_USER}:${LINUX_USER}" "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"
  systemctl enable "hermes-gateway@${LINUX_USER}.service" || true
  systemctl restart "hermes-gateway@${LINUX_USER}.service" || \
    echo "VAROITUS: hermes-gateway@${LINUX_USER} restart failed — tarkista LLM/SA"
done

if [[ "${TRANSPORT}" != "pubsub" ]] && command -v tailscale >/dev/null 2>&1; then
  bash "${ROOT}/deploy/host/tailscale-funnel.sh" || true
fi

echo "OK — host sync valmis (transport=${TRANSPORT}, gateway_host=${GATEWAY_HOST})"
