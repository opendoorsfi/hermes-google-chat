#!/usr/bin/env bash
# Export azuracast-sync standalone-repoksi.
#
#   bash scripts/export_azuracast_sync_repo.sh
#   bash scripts/export_azuracast_sync_repo.sh /tmp/azuracast-sync-export
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-/tmp/azuracast-sync-export}"

rm -rf "${DEST}"
mkdir -p "${DEST}"

tar -C "${HERE}" \
  --exclude='.pytest_cache' \
  --exclude='__pycache__' \
  --exclude='.git' \
  -cf - . | tar -C "${DEST}" -xf -

# Siirrä workflowt repojuureen (standalone)
if [[ -d "${DEST}/.github/workflows" ]]; then
  mkdir -p "${DEST}/.github/workflows"
fi

cd "${DEST}"
git init -b main 2>/dev/null || git init
git checkout -b main 2>/dev/null || true
git add -A
git commit -m "feat: azuracast-sync self-heal export" || true
echo "OK: ${DEST}"
