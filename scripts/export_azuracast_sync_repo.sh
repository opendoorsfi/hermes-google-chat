#!/usr/bin/env bash
# Wrapper: export azuracast-sync/ standalone-repoksi.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "${ROOT}/azuracast-sync/scripts/export_azuracast_sync_repo.sh" "$@"
