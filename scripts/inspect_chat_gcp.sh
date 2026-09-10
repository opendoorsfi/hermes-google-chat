#!/usr/bin/env bash
# Hae GCP Chat-infra (Pub/Sub, SA, API) — GitHub Actions WIF.
set -euo pipefail

GCP_PROJECT="${GCP_PROJECT:-od-azuracast-sync}"
TOPIC="${TOPIC:-hermes-chat-events}"
SUB="${SUB:-hermes-chat-events-sub}"

section() { echo ""; echo "=== $* ==="; }

section "Project"
gcloud projects describe "${GCP_PROJECT}" --format="yaml(projectId,name,projectNumber,lifecycleState)" 2>/dev/null || echo "VAROITUS: project describe epäonnistui"

section "Chat API enabled?"
gcloud services list --project="${GCP_PROJECT}" --filter="config.name:chat.googleapis.com" --format="table(config.name,state)" 2>/dev/null || true

section "Pub/Sub topic: ${TOPIC}"
if gcloud pubsub topics describe "${TOPIC}" --project="${GCP_PROJECT}" --format=yaml 2>/tmp/hermes_inspect_topic.err; then
  gcloud pubsub topics describe "${TOPIC}" --project="${GCP_PROJECT}" --format=yaml
else
  echo "VAROITUS: topic puuttuu tai ei oikeuksia"
  sed 's/^/  /' /tmp/hermes_inspect_topic.err || true
fi

section "Pub/Sub subscription: ${SUB}"
if gcloud pubsub subscriptions describe "${SUB}" --project="${GCP_PROJECT}" --format=yaml 2>/tmp/hermes_inspect_sub.err; then
  gcloud pubsub subscriptions describe "${SUB}" --project="${GCP_PROJECT}" --format=yaml
  echo ""
  echo "Undelivered (approx):"
  gcloud pubsub subscriptions pull "${SUB}" --project="${GCP_PROJECT}" --limit=1 --auto-ack=false 2>/dev/null \
    && echo "(viestejä jonossa — pull onnistui)" || echo "(ei viestejä tai ei pull-oikeutta)"
else
  echo "VAROITUS: subscription puuttuu tai ei oikeuksia"
  sed 's/^/  /' /tmp/hermes_inspect_sub.err || true
fi

section "Topic IAM (Chat publisher)"
gcloud pubsub topics get-iam-policy "${TOPIC}" --project="${GCP_PROJECT}" --format=yaml 2>/dev/null || echo "VAROITUS: topic IAM ei luettavissa"

section "Hermes Chat service accounts"
gcloud iam service-accounts list --project="${GCP_PROJECT}" \
  --filter="email~hermes-chat OR displayName:Hermes" \
  --format="table(email,displayName,disabled)" 2>/dev/null || true

section "Secret Manager (Chat SA)"
for s in hermes-google-chat-sa-json hermes-chat-sa-ipad hermes-chat-sa-natalia; do
  if gcloud secrets describe "${s}" --project="${GCP_PROJECT}" &>/dev/null; then
    echo "OK: secret ${s} exists"
  else
    echo "--: secret ${s} (ei löydy)"
  fi
done

section "Registry manifest (repo)"
if [[ -f config/tenants/registry.json ]]; then
  python3 scripts/chat_registry.py summary 2>/dev/null || true
fi

section "Huom: Chat App name / Visibility / Live-status"
echo "GCP ei tarjoa API:ta Console Configuration -kentille."
echo "Tarkista manuaalisesti (admin-oikeudet):"
echo "  https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat?project=${GCP_PROJECT}"
echo ""
echo "Repo/registry odottaa (ipad):"
echo "  App name: Hermes (Ipad)"
echo "  Allowed:  ipad@info.opendoors.fi"
echo "  Transport: Pub/Sub → projects/${GCP_PROJECT}/topics/${TOPIC}"
