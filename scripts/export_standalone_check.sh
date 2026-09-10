#!/usr/bin/env bash
# Verify repo is ready for standalone use (workflows, tenants, docs).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"
make validate
test -f .github/workflows/ci.yml
test -f .github/workflows/tenant-gcp.yml
test -f docs/MULTI_TENANT.md
echo "OK — standalone-ready"
