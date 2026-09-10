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
