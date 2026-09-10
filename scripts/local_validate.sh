#!/usr/bin/env bash
# Local validation without GCP credentials.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

echo "==> pytest"
python3 -m pytest tests/ -v

echo "==> shell syntax"
bash -n infra/setup_gcp.sh
bash -n deploy/cloudrun/deploy.sh
bash -n deploy/entrypoint.sh
for s in scripts/*.sh; do bash -n "$s"; done

echo "==> required files"
for f in deploy/Dockerfile deploy/entrypoint.sh config/hermes.env.example \
  profiles/opendoors/config.yaml docs/RUNBOOK.md; do
  test -f "$f" || { echo "missing $f"; exit 1; }
done

if command -v docker >/dev/null 2>&1; then
  echo "==> docker build"
  DOCKER="${DOCKER:-docker}"
  if ! ${DOCKER} info >/dev/null 2>&1; then
    DOCKER="sudo docker"
  fi
  ${DOCKER} build -t hermes-google-chat:local -f deploy/Dockerfile .
  echo "docker build ok"
else
  echo "==> skip docker (not installed)"
fi

echo ""
echo "OK — local validation passed"
