#!/usr/bin/env bash
# Cloud Agent install: idempotent dev/test tooling for hermes-google-chat.
#
# The dev flow is `make validate` (pytest + shellcheck) and `make standalone-check`.
# Tools are installed from PyPI because the default Ubuntu apt mirrors are not
# reliably reachable in this environment; shellcheck-py bundles the `shellcheck`
# binary that `make lint` invokes.
set -euo pipefail

cd "$(dirname "$0")/.."

pip_args=(--break-system-packages --upgrade -r requirements-dev.txt shellcheck-py)

# Prefer a system-wide install so console scripts land in /usr/local/bin (always
# on PATH). Fall back to a user install (~/.local/bin, on PATH in login shells)
# when passwordless sudo is unavailable.
if sudo -n true 2>/dev/null; then
  sudo python3 -m pip install "${pip_args[@]}"
else
  python3 -m pip install "${pip_args[@]}"
fi

echo "install.sh: pytest + shellcheck ready"
python3 -m pytest --version
shellcheck --version | head -2
