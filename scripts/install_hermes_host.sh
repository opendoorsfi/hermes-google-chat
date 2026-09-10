#!/usr/bin/env bash
# Install Hermes multi-tenant host: Linux users, Caddy, systemd.
#
#   sudo bash scripts/install_hermes_host.sh --all
#   sudo bash scripts/install_hermes_host.sh --tenant alice
#
# Prerequisites: hermes CLI in /usr/local/bin/hermes, caddy installed.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/scripts/lib/tenant.sh"

TENANTS=()
DO_ALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant) TENANTS+=("$2"); shift 2 ;;
    --all) DO_ALL=true; shift ;;
    -h|--help)
      echo "Usage: sudo $0 --all | --tenant NAME [--tenant NAME2 ...]"
      exit 0
      ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "VIRHE: aja rootina (sudo)"
  exit 1
fi

if [[ "${DO_ALL}" == true ]]; then
  mapfile -t TENANTS < <(list_tenants)
fi

if [[ ${#TENANTS[@]} -eq 0 ]]; then
  echo "VIRHE: --tenant NAME tai --all"
  exit 1
fi

if ! command -v caddy >/dev/null 2>&1; then
  echo "VIRHE: caddy puuttuu. Asenna: https://caddyserver.com/docs/install"
  exit 1
fi

if ! command -v hermes >/dev/null 2>&1 && [[ ! -x /usr/local/bin/hermes ]]; then
  echo "VAROITUS: hermes CLI ei löydy /usr/local/bin/hermes — asenna ennen gateway-käynnistystä"
fi

mkdir -p /etc/hermes/tenants
CADDY_BLOCKS=""

for tenant in "${TENANTS[@]}"; do
  load_tenant "${tenant}"
  echo "==> Tenant ${tenant}: user=${LINUX_USER} port=${PORT} path=${PATH_PREFIX}"

  if ! id "${LINUX_USER}" &>/dev/null; then
    useradd -m -s /bin/bash "${LINUX_USER}"
    echo "    Created user ${LINUX_USER}"
  fi

  install -d -m 700 -o "${LINUX_USER}" -g "${LINUX_USER}" "/home/${LINUX_USER}/.hermes"
  install -d -m 700 -o "${LINUX_USER}" -g "${LINUX_USER}" "/home/${LINUX_USER}/.hermes/secrets"

  cat > "/etc/hermes/tenants/${LINUX_USER}.env" <<EOF
API_SERVER_PORT=${PORT}
GOOGLE_CHAT_PROJECT_ID=${GCP_PROJECT}
HERMES_CHAT_TRANSPORT=http
TENANT=${tenant}
EOF
  chmod 644 "/etc/hermes/tenants/${LINUX_USER}.env"

  prefix="${PATH_PREFIX}"
  prefix="${prefix#/}"
  CADDY_BLOCKS+=$'\t'"handle_path /${prefix}/* {"$'\n'
  CADDY_BLOCKS+=$'\t\t'"reverse_proxy 127.0.0.1:${PORT}"$'\n'
  CADDY_BLOCKS+=$'\t'"}"$'\n\n'

done

TEMPLATE="$(cat "${ROOT}/deploy/host/Caddyfile.template")"
CADDYFILE="${TEMPLATE//\{\{TENANT_BLOCKS\}\}/${CADDY_BLOCKS}}"
install -m 644 /dev/stdin /etc/hermes/Caddyfile <<< "${CADDYFILE}"

install -m 644 "${ROOT}/deploy/systemd/caddy-hermes.service" /etc/systemd/system/caddy-hermes.service
install -m 644 "${ROOT}/deploy/systemd/hermes-gateway@.service" /etc/systemd/system/hermes-gateway@.service

systemctl daemon-reload
systemctl enable caddy-hermes.service
systemctl restart caddy-hermes.service || echo "VAROITUS: caddy restart failed — tarkista journalctl"

for tenant in "${TENANTS[@]}"; do
  load_tenant "${tenant}"
  systemctl enable "hermes-gateway@${LINUX_USER}.service" || true
  echo "    systemctl start hermes-gateway@${LINUX_USER}.service  # after .env configured"
done

echo ""
echo "OK — host asennus valmis."
echo "Seuraavaksi per tenant:"
echo "  1. bash scripts/print_tenant_env.sh TENANT >> /home/USER/.hermes/.env"
echo "  2. Kopioi SA JSON → /home/USER/.hermes/secrets/google-chat-sa.json"
echo "  3. systemctl start hermes-gateway@USER"
echo "  4. sudo bash deploy/host/tailscale-funnel.sh"
echo "  5. bash scripts/verify_tenant.sh TENANT"
