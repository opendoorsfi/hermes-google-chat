#!/usr/bin/env bash
# Kerran (GCP admin): valmistele od-kansiot Hermes Google Chat -projektille.
#
#   bash scripts/bootstrap_od_kansiot_project.sh
#
# 1. Pub/Sub + SA (setup_gcp.sh)
# 2. Deploy-SA IAM (grant_deploy_sa_chat.sh)
# 3. WIF GitHubille (setup_github_wif.sh)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GCP_PROJECT="${GCP_PROJECT:-od-kansiot}"
export HERMES_CHAT_TRANSPORT=pubsub

echo "==> Hermes GCP bootstrap: ${GCP_PROJECT}"
bash "${ROOT}/infra/setup_gcp.sh"
bash "${ROOT}/scripts/grant_deploy_sa_chat.sh"
bash "${ROOT}/scripts/setup_github_wif.sh"
echo ""
echo "Seuraavaksi:"
echo "  1. Aja bootstrap_github_secrets.sh (GitHub secrets)"
echo "  2. Commit registry wif_provider"
echo "  3. GitHub Actions → Sync Chat users"
echo "  4. Console → hermes-chat app Save (ks. out/chat-app/CHAT_APP_SETUP.md)"
