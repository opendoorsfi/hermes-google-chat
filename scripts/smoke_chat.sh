#!/usr/bin/env bash
# Post-deploy smoke: Cloud Run up + Pub/Sub subscription exists.
set -euo pipefail

GCP_PROJECT="${GCP_PROJECT:?Set GCP_PROJECT}"
GCP_REGION="${GCP_REGION:-europe-north1}"
SERVICE="${SERVICE:-hermes-gateway}"

echo "==> Cloud Run service ${SERVICE}"
gcloud run services describe "${SERVICE}" \
  --project="${GCP_PROJECT}" \
  --region="${GCP_REGION}" \
  --format="table(status.url,status.conditions[0].type,status.conditions[0].status)"

echo ""
echo "==> Recent logs (look for GoogleChat Connected)"
gcloud run services logs read "${SERVICE}" \
  --project="${GCP_PROJECT}" \
  --region="${GCP_REGION}" \
  --limit=30 2>/dev/null || echo "(logs require permission)"

echo ""
bash "$(dirname "$0")/verify_pubsub.sh"

echo ""
echo "Manual: send 'hola' in Chat DM/space → expect reply within ~30s"
