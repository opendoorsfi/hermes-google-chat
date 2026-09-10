#!/usr/bin/env bash
# Apply registry tenants on macOS Hermes host (self-hosted runner, no sudo).
#
#   bash scripts/sync_mac_from_registry.sh
#   HERMES_REGISTRY_HOST=natalia-mac bash scripts/sync_mac_from_registry.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "VIRHE: macOS-skripti — Linux: sudo bash scripts/sync_host_from_registry.sh"
  exit 1
fi

python3 scripts/chat_registry.py generate-all

HOST_ID="${HERMES_REGISTRY_HOST:-}"
if [[ -z "${HOST_ID}" ]]; then
  TS_HOST="$(tailscale status --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('Self', {}).get('DNSName', '').rstrip('.').split('.')[0])
" 2>/dev/null || true)"
  if [[ -n "${TS_HOST}" ]]; then
    HOST_ID="$(python3 -c "
import json, pathlib
reg = json.loads(pathlib.Path('config/tenants/registry.json').read_text())
hosts = reg.get('hosts') or {}
ts = '${TS_HOST}'.lower()
for hid, cfg in hosts.items():
    funnel = str(cfg.get('funnel_base_url', '')).lower()
    if ts in funnel or funnel.endswith('//' + ts) or '/'+ts+'.' in funnel:
        print(hid)
        break
" 2>/dev/null || true)"
  fi
fi

if [[ -z "${HOST_ID}" ]]; then
  echo "VIRHE: HERMES_REGISTRY_HOST puuttuu eikä hostia tunnistettu Tailscalesta"
  echo "  export HERMES_REGISTRY_HOST=natalia-mac"
  exit 1
fi

echo "==> macOS host sync (registry host: ${HOST_ID})"

mapfile -t EMAILS < <(python3 -c "
import json, subprocess
users = json.loads(subprocess.check_output(['python3', 'scripts/chat_registry.py', 'host-users', '${HOST_ID}']))
for u in users:
    print(u['GOOGLE_CHAT_ALLOWED_USERS'])
")

if [[ ${#EMAILS[@]} -eq 0 ]]; then
  echo "VAROITUS: ei käyttäjiä hostille ${HOST_ID}"
  exit 0
fi

for email in "${EMAILS[@]}"; do
  echo "==> bootstrap: ${email}"
  bash "${ROOT}/scripts/bootstrap_hermes_mac.sh" "${email}"
done

echo "OK — mac host sync valmis (${#EMAILS[@]} user(s) on ${HOST_ID})"
