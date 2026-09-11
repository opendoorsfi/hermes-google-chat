#!/usr/bin/env bash
# Tarkista Pub/Sub gateway (macOS tai Linux).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
ENV_FILE="${HERMES_HOME}/.env"
FAIL=0

echo "=== Pub/Sub gateway verify ==="

for key in HERMES_CHAT_TRANSPORT GOOGLE_CHAT_SUBSCRIPTION_NAME GOOGLE_CHAT_PROJECT_ID; do
  if grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
    echo "OK: ${key}"
  else
    echo "VIRHE: ${key} puuttuu ${ENV_FILE}"
    FAIL=1
  fi
done

TRANSPORT="$(grep -E '^HERMES_CHAT_TRANSPORT=' "${ENV_FILE}" 2>/dev/null | cut -d= -f2- || true)"
if [[ "${TRANSPORT}" != "pubsub" ]]; then
  echo "VIRHE: HERMES_CHAT_TRANSPORT=${TRANSPORT:-unset} (pitää olla pubsub)"
  FAIL=1
fi

if grep -qE '^GOOGLE_CHAT_HTTP_EVENTS_URL=' "${ENV_FILE}" 2>/dev/null; then
  echo "VAROITUS: HTTP_EVENTS_URL .env:ssä — voi estää Pub/Sub-inboundin"
  FAIL=1
fi

if [[ -s "${HERMES_HOME}/secrets/google-chat-sa.json" ]]; then
  echo "OK: SA JSON olemassa"
elif grep -q '^GOOGLE_CHAT_IMPERSONATE_SERVICE_ACCOUNT=' "${ENV_FILE}" 2>/dev/null; then
  echo "OK: ADC impersonation"
else
  echo "VIRHE: ei SA JSON eikä impersonation"
  FAIL=1
fi

if command -v hermes >/dev/null 2>&1; then
  if hermes gateway status 2>/dev/null | grep -qiE 'running|active|connected'; then
    echo "OK: hermes gateway status"
  elif pgrep -fl "hermes.*gateway" >/dev/null 2>&1; then
    echo "OK: hermes gateway prosessi käynnissä"
  else
    echo "VIRHE: hermes gateway ei käynnissä"
    FAIL=1
  fi
else
  echo "VAROITUS: hermes CLI puuttuu"
fi

for log in "${HERMES_HOME}/logs/gateway.log" "${HERMES_HOME}/logs/gateway.err"; do
  [[ -f "${log}" ]] || continue
  if grep -qiE 'GoogleChat.*Connected|subscription=' "${log}" 2>/dev/null; then
    echo "OK: GoogleChat connected (${log})"
    grep -iE 'GoogleChat|subscription' "${log}" 2>/dev/null | tail -3 | sed 's/^/    /'
  elif grep -qiE 'error|traceback|permission|denied' "${log}" 2>/dev/null; then
    echo "VAROITUS: virheitä logissa ${log}:"
    grep -iE 'error|traceback|permission|denied' "${log}" 2>/dev/null | tail -5 | sed 's/^/    /'
    FAIL=1
  fi
done

if command -v gcloud >/dev/null 2>&1; then
  SUB="$(python3 "${ROOT}/scripts/chat_registry.py" hub-json | python3 -c "import json,sys; print(json.load(sys.stdin)['pubsub_subscription_full'])")"
  GCP="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['gcp_project'])" "$(python3 "${ROOT}/scripts/chat_registry.py" hub-json)")"
  if gcloud pubsub subscriptions describe "${SUB#projects/${GCP}/subscriptions/}" --project="${GCP}" --format="value(name)" >/dev/null 2>&1; then
    echo "OK: subscription ${SUB}"
  fi
fi

if [[ "${FAIL}" == "0" ]]; then
  echo ""
  echo "OK — Pub/Sub gateway näyttää kunnossa"
  exit 0
fi
echo ""
echo "VIRHE — korjaa: bash scripts/sync_mac_pubsub_from_registry.sh"
exit 1
