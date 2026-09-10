#!/usr/bin/env bash
# Guide + checks for adding Hermes bot to a Google Chat space.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

cat <<'EOF'
==> Google Chat space bootstrap

1. APIs & Services → Google Chat API → Configuration
   - Connection: Cloud Pub/Sub
   - Topic: projects/YOUR_PROJECT/topics/hermes-chat-events

2. Google Chat → + New chat → search app name → DM or add to space

3. Send: hola

4. Verify:
   bash scripts/verify_pubsub.sh
   gcloud run services logs read hermes-gateway --region=europe-north1 --limit=50

5. Set GOOGLE_CHAT_HOME_CHANNEL to your space ID (spaces/...) in deploy env
EOF

if [[ -n "${GCP_PROJECT}" && "${GCP_PROJECT}" != "(unset)" ]]; then
  bash "${ROOT}/scripts/verify_pubsub.sh" || true
fi
