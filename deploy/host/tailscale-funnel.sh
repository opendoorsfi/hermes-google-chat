#!/usr/bin/env bash
# Expose Caddy :8443 via Tailscale Funnel (public HTTPS for Google Chat inbound).
#
#   sudo bash deploy/host/tailscale-funnel.sh
#
# Requires: tailscale logged in, Funnel enabled for tailnet.

set -euo pipefail

CADDY_PORT="${CADDY_PORT:-8443}"

if ! command -v tailscale >/dev/null 2>&1; then
  echo "VIRHE: tailscale ei asennettu"
  exit 1
fi

echo "==> Tailscale serve: HTTPS → localhost:${CADDY_PORT}"
tailscale serve --bg --https=443 "http://127.0.0.1:${CADDY_PORT}"

echo "==> Tailscale funnel (julkinen HTTPS Google Chatille)"
tailscale funnel --bg 443

HOSTNAME="$(tailscale status --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('Self',{}).get('DNSName','').rstrip('.'))
" 2>/dev/null || tailscale status --self 2>/dev/null | head -1 || echo "unknown")"

echo ""
echo "OK — Funnel base URL (päivitä config/tenants/*.env FUNNEL_BASE_URL):"
echo "  https://${HOSTNAME}"
echo ""
echo "Esimerkki alice endpoint:"
echo "  https://${HOSTNAME}/alice/api/platforms/google_chat/events"
