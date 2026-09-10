#!/usr/bin/env bash
# Outbound Chat auth (ADC impersonation — org policy estää SA JSON -avaimet).
#   bash scripts/refresh_chat_sa.sh natalia --restart
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec bash "${ROOT}/setup_chat_outbound_auth.sh" "${1:-natalia}" "${2:---restart}"
