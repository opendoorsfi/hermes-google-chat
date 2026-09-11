#!/usr/bin/env bash
# Kertaluontoinen Hermes Google Chat -host (ubuntu-work-h tms.) — Pub/Sub (Hermes docs).
#
#   git clone git@github.com:opendoorsfi/hermes-google-chat.git
#   cd hermes-google-chat && sudo bash scripts/bootstrap_hermes_host.sh
#
# Vaatii: git-repo, hermes CLI (/usr/local/bin/hermes).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "VIRHE: aja sudo bash scripts/bootstrap_hermes_host.sh"
  exit 1
fi

echo "==> Hermes Google Chat host bootstrap (Pub/Sub)"
echo "    repo: ${ROOT}"

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

HUB="$(python3 scripts/chat_registry.py hub-json)"
SUB="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['pubsub_subscription_full'])" "${HUB}")"
CONSOLE="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['console_url'])" "${HUB}")"

echo ""
echo "==> Pub/Sub subscription: ${SUB}"
echo "==> Seuraavaksi (jos gateway ei vastaa Chatissa):"
echo "  1. SA JSON → /home/hermes-ipad/.hermes/secrets/google-chat-sa.json"
echo "     (GitHub Actions artefakti tenant-ipad-gcp tai Secret Manager)"
echo "  2. LLM-avain → /home/hermes-ipad/.hermes/.env (OPENROUTER_API_KEY=...)"
echo "  3. sudo systemctl restart hermes-gateway@hermes-ipad"
echo "  4. Console → Chat API → Connection = Pub/Sub:"
echo "     ${CONSOLE}"
echo "  5. Chatissa: Find apps → hermes-chat → Message → Hei"
echo ""
echo "==> (Valinnainen) GitHub Actions runner — automaattinen host sync:"
echo "  https://github.com/opendoorsfi/hermes-google-chat/settings/actions/runners/new"
echo "  Labels: hermes-host, self-hosted"
echo ""
echo "OK — host bootstrap valmis."
