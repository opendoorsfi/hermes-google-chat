#!/usr/bin/env bash
# Simuloi Chat-viesti Pub/Sub-topicille → Hermes vastaa Google Chatiin.
#
#   EMAIL=ipad@info.opendoors.fi TEXT="Hei" bash scripts/publish_chat_inbound_test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HUB="$(python3 "${ROOT}/scripts/chat_registry.py" hub-json 2>/dev/null || echo '{}')"
GCP_PROJECT="${GCP_PROJECT:-$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('gcp_project','opendoors-hermes-chat'))" "${HUB}")}"
TOPIC="${TOPIC:-$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('pubsub_topic','hermes-chat-events'))" "${HUB}")}"
EMAIL="${EMAIL:-opendoorsfinland@gmail.com}"
TEXT="${TEXT:-Hei — testi Hermes-pubsubista $(date -u +%H:%M:%S)}"
EVENT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

export EMAIL TEXT EVENT_TIME

payload="$(python3 - <<'PY'
import json, os
email = os.environ.get("EMAIL", "ipad@info.opendoors.fi")
text = os.environ.get("TEXT", "Hei — Hermes pubsub-testi")
event_time = os.environ.get("EVENT_TIME", "")
if not event_time:
    from datetime import datetime, timezone
    event_time = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
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
