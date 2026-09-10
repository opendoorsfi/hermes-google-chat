#!/usr/bin/env bash
# Apply all registry tenants on Hermes host (self-hosted runner or SSH).
#   sudo bash scripts/sync_host_from_registry.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "VIRHE: aja rootina (sudo) — systemd + useradd"
  exit 1
fi

python3 scripts/chat_registry.py generate-all

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
# Ilman niitä google_chat-adapter ei käynnisty → API server vastaa 503.
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

for t in "${TENANTS[@]}"; do
  echo "==> ${t}: SA JSON"
  bash "${ROOT}/scripts/ensure_tenant_sa.sh" "${t}" || true
  # shellcheck source=scripts/lib/tenant.sh
  source "${ROOT}/scripts/lib/tenant.sh"
  load_tenant "${t}"
  ENV_FILE="/home/${LINUX_USER}/.hermes/.env"
  MARKER="# --- Google Chat tenant ${t} (generated) ---"
  if [[ -f "${ENV_FILE}" ]] && grep -qF "${MARKER}" "${ENV_FILE}" 2>/dev/null; then
    echo "==> ${t}: .env block already present"
    # Vanha lohko ilman API server -asetuksia → täydennä (muuten Funnel/Caddy antaa 502)
    if ! grep -q '^API_SERVER_KEY=' "${ENV_FILE}" 2>/dev/null; then
      {
        echo "API_SERVER_ENABLED=true"
        echo "API_SERVER_HOST=127.0.0.1"
        echo "API_SERVER_PORT=${PORT}"
        echo "API_SERVER_KEY=$(openssl rand -hex 32 2>/dev/null || python3 -c 'import secrets; print(secrets.token_hex(32))')"
      } >> "${ENV_FILE}"
      echo "==> ${t}: lisätty API_SERVER_* .env:iin"
    fi
  else
    bash "${ROOT}/scripts/print_tenant_env.sh" "${t}" >> "${ENV_FILE}"
    if [[ -f "/home/${LINUX_USER}/.hermes/secrets/google-chat-sa.json" ]]; then
      if ! grep -q '^GOOGLE_APPLICATION_CREDENTIALS=' "${ENV_FILE}" 2>/dev/null; then
        echo "GOOGLE_APPLICATION_CREDENTIALS=/home/${LINUX_USER}/.hermes/secrets/google-chat-sa.json" >> "${ENV_FILE}"
      fi
    fi
    chown "${LINUX_USER}:${LINUX_USER}" "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
    echo "==> ${t}: appended Chat block to ${ENV_FILE}"
  fi
  systemctl enable "hermes-gateway@${LINUX_USER}.service" || true
  systemctl restart "hermes-gateway@${LINUX_USER}.service" || \
    echo "VAROITUS: hermes-gateway@${LINUX_USER} restart failed — tarkista LLM/SA"
done

if command -v tailscale >/dev/null 2>&1; then
  bash "${ROOT}/deploy/host/tailscale-funnel.sh" || true
fi

echo "OK — host sync valmis (${#TENANTS[@]} tenant(s))"
