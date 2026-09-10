#!/usr/bin/env bash
# End-to-end tenant provisioning helper (GCP + host instructions).
#
#   TENANT=alice bash scripts/provision_tenant.sh
#   TENANT=alice bash scripts/provision_tenant.sh --gcp-only
#   TENANT=alice bash scripts/provision_tenant.sh --host-only

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GCP_ONLY=false
HOST_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --gcp-only) GCP_ONLY=true ;;
    --host-only) HOST_ONLY=true ;;
  esac
done

TENANT="${TENANT:?Set TENANT=alice}"
# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/scripts/lib/tenant.sh"
load_tenant "${TENANT}"

echo "==> Provision tenant: ${TENANT} (${ROLE})"

if [[ "${HOST_ONLY}" != true ]]; then
  bash "${ROOT}/infra/setup_tenant_gcp.sh"
fi

if [[ "${GCP_ONLY}" != true ]]; then
  if [[ "${EUID}" -eq 0 ]]; then
    bash "${ROOT}/scripts/install_hermes_host.sh" --tenant "${TENANT}"
  else
    echo "Host-asennus: sudo bash scripts/install_hermes_host.sh --tenant ${TENANT}"
  fi
fi

echo ""
echo "==> .env block for /home/${LINUX_USER}/.hermes/.env:"
bash "${ROOT}/scripts/print_tenant_env.sh" "${TENANT}"
