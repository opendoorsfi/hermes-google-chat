#!/usr/bin/env bash
# Kertaluontoinen Hermes Google Chat -host (ubuntu-work-h tms.).
#
#   git clone git@github.com:opendoorsfi/hermes-google-chat.git
#   cd hermes-google-chat && sudo bash scripts/bootstrap_hermes_host.sh
#
# Vaatii: tailscale login, git-repo, hermes CLI (/usr/local/bin/hermes),
#         caddy (asennetaan Debian/Ubuntu jos puuttuu).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "VIRHE: aja sudo bash scripts/bootstrap_hermes_host.sh"
  exit 1
fi

echo "==> Hermes Google Chat host bootstrap"
echo "    repo: ${ROOT}"

if ! command -v tailscale >/dev/null 2>&1; then
  echo "VIRHE: tailscale puuttuu — asenna ensin: https://tailscale.com/download/linux"
  exit 1
fi
if ! tailscale status >/dev/null 2>&1; then
  echo "VIRHE: tailscale ei ole päällä — aja: sudo tailscale up"
  exit 1
fi

if ! command -v caddy >/dev/null 2>&1; then
  echo "==> Asennetaan Caddy..."
  apt-get update -qq
  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq && apt-get install -y -qq caddy
fi

if ! command -v hermes >/dev/null 2>&1 && [[ ! -x /usr/local/bin/hermes ]]; then
  echo "VIRHE: hermes CLI puuttuu (/usr/local/bin/hermes)."
  echo "  Asenna Hermes ensin — ks. https://hermes-agent.nousresearch.com/"
  exit 1
fi

if [[ ! -f config/tenants/registry.json ]]; then
  echo "VIRHE: config/tenants/registry.json puuttuu — git pull?"
  exit 1
fi

python3 scripts/chat_registry.py generate-all
bash scripts/sync_host_from_registry.sh

FUNNEL="$(python3 -c "import json; print(json.load(open('config/tenants/registry.json'))['funnel_base_url'])")"
echo ""
echo "==> Tarkista Funnel (odotus: ${FUNNEL})"
curl -sS -o /dev/null -w "POST /ipad → HTTP %{http_code}\n" \
  -X POST "${FUNNEL%/}/ipad/api/platforms/google_chat/events" \
  -H 'Content-Type: application/json' -d '{}' || true

echo ""
echo "==> Seuraavaksi (jos gateway ei käynnisty):"
echo "  1. SA JSON → /home/hermes-ipad/.hermes/secrets/google-chat-sa.json"
echo "     GCP: IAM → hermes-chat-ipad@od-azuracast-sync.iam.gserviceaccount.com → Keys"
echo "  2. LLM-avain → /home/hermes-ipad/.hermes/.env (OPENROUTER_API_KEY=...)"
echo "  3. sudo systemctl restart hermes-gateway@hermes-ipad"
echo "  4. Google Chat API Console → HTTP URL:"
echo "     ${FUNNEL%/}/ipad/api/platforms/google_chat/events"
echo ""
echo "==> (Valinnainen) GitHub Actions runner — jotta uudet käyttäjät tulevat automaattisesti:"
echo "  https://github.com/opendoorsfi/hermes-google-chat/settings/actions/runners/new"
echo "  Labels: hermes-host, self-hosted"
echo ""
echo "OK — host bootstrap valmis."
