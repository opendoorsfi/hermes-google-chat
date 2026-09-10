#!/usr/bin/env bash
# Smoke-check tenant HTTP endpoint (expect 401 without Chat JWT) + manifest sanity.
#
#   bash scripts/verify_tenant.sh alice

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/scripts/lib/tenant.sh"

TENANT="${1:?Usage: verify_tenant.sh TENANT}"
load_tenant "${TENANT}"

EVENTS_URL="$(tenant_chat_http_url)"
echo "==> Tenant ${TENANT} (${ROLE})"
echo "    GCP project: ${GCP_PROJECT}"
echo "    HTTP events: ${EVENTS_URL}"
echo "    Local port:  ${PORT}"

CODE="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${EVENTS_URL}" \
  -H 'Content-Type: application/json' -d '{}' || echo "000")"

if [[ "${CODE}" == "401" || "${CODE}" == "403" ]]; then
  echo "OK — endpoint reachable, auth rejected as expected (HTTP ${CODE})"
elif [[ "${CODE}" == "000" ]]; then
  echo "VAROITUS: endpoint unreachable (curl failed). Caddy/Funnel/gateway running?"
  exit 1
else
  echo "VAROITUS: unexpected HTTP ${CODE} (expected 401/403 without JWT)"
  exit 1
fi

if command -v gcloud >/dev/null 2>&1; then
  if gcloud projects describe "${GCP_PROJECT}" &>/dev/null; then
    echo "OK — GCP project ${GCP_PROJECT} exists"
  else
    echo "VAROITUS: GCP project ${GCP_PROJECT} not found or no access"
  fi
fi

echo "Manual: send DM/space message to ${CHAT_APP_DISPLAY_NAME}, check journal:"
echo "  journalctl -u hermes-gateway@${TENANT} -n 30 --no-pager"
