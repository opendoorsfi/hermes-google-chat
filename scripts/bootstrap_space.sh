#!/usr/bin/env bash
# Guide: add Hermes bot to a Google Chat space (HTTP + Funnel -malli).
#
#   TENANT=team bash scripts/bootstrap_space.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TENANT="${TENANT:-team}"
# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/scripts/lib/tenant.sh"
load_tenant "${TENANT}"

EVENTS_URL="$(tenant_chat_http_url)"

cat <<EOF
==> Google Chat space bootstrap (tenant: ${TENANT})

1. GCP Console → projekti ${GCP_PROJECT} → Google Chat API → Configuration
   - Connection: HTTP endpoint URL
   - URL: ${EVENTS_URL}
   - Visibility: ${GOOGLE_CHAT_ALLOWED_USERS}

2. Google Chat → Spaces → Create space (tai DM henkilöboteille)
   - Manage apps → Add → "${CHAT_APP_DISPLAY_NAME}"

3. Lähetä: hola

4. Verify:
   bash scripts/verify_tenant.sh ${TENANT}
   journalctl -u hermes-gateway@${LINUX_USER} -n 50 --no-pager

5. (Valinnainen) Aseta home channel Hermes-env:iin:
   GOOGLE_CHAT_HOME_CHANNEL=spaces/AAAAxxxxxxxx

Täysi asennus: docs/GOOGLE_CHAT_INSTALL.md
EOF

if command -v curl >/dev/null 2>&1; then
  bash "${ROOT}/scripts/verify_tenant.sh" "${TENANT}" || true
fi
