#!/usr/bin/env bash
# Standalone export (aja repojuuresta tai moderate-monorepossa).
#
#   bash scripts/export_repo.sh
#   bash scripts/export_repo.sh /tmp/my-export

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "${HERE}/../scripts/export_hermes_google_chat_repo.sh" ]]; then
  exec bash "${HERE}/../scripts/export_hermes_google_chat_repo.sh" "$@"
fi

# Already standalone — archive current repo for backup
DEST="${1:-/tmp/hermes-google-chat-export}"
rm -rf "${DEST}"
mkdir -p "${DEST}"
tar -C "${HERE}" \
  --exclude='.pytest_cache' \
  --exclude='__pycache__' \
  --exclude='out' \
  --exclude='.git' \
  --exclude='.cursor' \
  -cf - . | tar -C "${DEST}" -xf -
cd "${DEST}"
git init -b main
git add -A
git commit -m "feat: hermes-google-chat standalone"
echo "OK: ${DEST}"
