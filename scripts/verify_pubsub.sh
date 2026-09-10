#!/usr/bin/env bash
# Check Pub/Sub subscription health for Hermes Chat events.
set -euo pipefail

GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
SUB="${SUB:-hermes-chat-events-sub}"

if [[ -z "${GCP_PROJECT}" || "${GCP_PROJECT}" == "(unset)" ]]; then
  echo "VIRHE: aseta GCP_PROJECT"
  exit 1
fi

echo "==> Subscription: ${SUB} (project ${GCP_PROJECT})"

gcloud pubsub subscriptions describe "${SUB}" \
  --project="${GCP_PROJECT}" \
  --format="yaml(name,topic,ackDeadlineSeconds,messageRetentionDuration,state)"

echo ""
echo "==> Undelivered (numUndeliveredMessages) — lähetä 'hola' Chatissa ja aja uudelleen"
gcloud monitoring metrics list --filter="metric.type=pubsub.googleapis.com/subscription/num_undelivered_messages" 2>/dev/null \
  || echo "(monitoring API optional; tarkista Console → Pub/Sub → subscription → Metrics)"

echo ""
echo "OK — subscription exists. Jos viestejä ei tule, tarkista Chat API topic + IAM (RUNBOOK.md)."
