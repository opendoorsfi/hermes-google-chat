#!/usr/bin/env bash
# Simuloi Chat-viesti Pub/Sub-topicille → Hermes vastaa Google Chatiin.
#
#   EMAIL=ipad@info.opendoors.fi TEXT="Hei" bash scripts/publish_chat_inbound_test.sh
set -euo pipefail

GCP_PROJECT="${GCP_PROJECT:-od-azuracast-sync}"
TOPIC="${TOPIC:-hermes-chat-events}"
EMAIL="${EMAIL:-ipad@info.opendoors.fi}"
TEXT="${TEXT:-Hei — testi Hermes-pubsubista $(date -u +%H:%M:%S)}"
EVENT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

payload="$(python3 - <<PY
import json, os
email = os.environ["EMAIL"]
text = os.environ["TEXT"]
event_time = os.environ["EVENT_TIME"]
print(json.dumps({
    "type": "MESSAGE",
    "eventTime": event_time,
    "user": {"email": email, "type": "HUMAN", "displayName": email.split("@")[0].title()},
    "space": {"type": "DM", "displayName": "DM"},
    "message": {
        "text": text,
        "argumentText": text,
        "sender": {"email": email, "type": "HUMAN", "displayName": email.split("@")[0].title()},
        "space": {"type": "DM"},
    },
}))
PY
)"

echo "==> Publish test MESSAGE → projects/${GCP_PROJECT}/topics/${TOPIC}"
echo "    from: ${EMAIL}"
echo "    text: ${TEXT}"

gcloud pubsub topics publish "${TOPIC}" \
  --project="${GCP_PROJECT}" \
  --message="${payload}" \
  --attribute="ce-type=google.chat.event.v1.message"

echo "OK — Hermes-gatewayin pitäisi vastata Chat-DM:ään ~30s (Pub/Sub → gateway → Chat API)"
