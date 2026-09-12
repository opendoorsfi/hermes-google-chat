#!/usr/bin/env bash
# Diagnostiikka + automaattinen korjaus Hermes Chat -gatewaylle (Cloud Run / Pub/Sub).
#
#   bash scripts/self_heal_gateway.sh          # vain diagnoosi
#   bash scripts/self_heal_gateway.sh --apply  # korjaa mitä pystyy (CI)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

HUB="$(python3 "${ROOT}/scripts/chat_registry.py" hub-json)"
GCP_PROJECT="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['gcp_project'])" "${HUB}")"
TOPIC="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['pubsub_topic'])" "${HUB}")"
SUB="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['pubsub_sub'])" "${HUB}")"
SUB_FULL="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['pubsub_subscription_full'])" "${HUB}")"
GATEWAY_HOST="$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('chat_gateway_host',''))" "${HUB}")"
REGION="${GCP_REGION:-europe-north1}"
SERVICE="${SERVICE_NAME:-hermes-gateway}"

ISSUES=()
FIXED=()

note_issue() { ISSUES+=("$1"); echo "ISSUE: $1"; }
note_fixed() { FIXED+=("$1"); echo "FIXED: $1"; }

section() { echo ""; echo "=== $* ==="; }

section "Diagnoosi — ${GCP_PROJECT} (gateway=${GATEWAY_HOST})"

if ! command -v gcloud >/dev/null 2>&1; then
  note_issue "gcloud puuttuu — aja GitHub Actionsissa tai asenna Cloud SDK"
  echo ""
  echo "Yhteenveto: ${#ISSUES[@]} ongelmaa, ${#FIXED[@]} korjausta"
  exit 1
fi

# --- Cloud Run ---
CR_READY=0
CR_URL=""
if gcloud run services describe "${SERVICE}" \
  --project="${GCP_PROJECT}" --region="${REGION}" &>/dev/null; then
  CR_URL="$(gcloud run services describe "${SERVICE}" \
    --project="${GCP_PROJECT}" --region="${REGION}" \
    --format='value(status.url)' 2>/dev/null || true)"
  if gcloud run services describe "${SERVICE}" \
    --project="${GCP_PROJECT}" --region="${REGION}" \
    --format='value(status.conditions.status)' 2>/dev/null | grep -q True; then
    echo "OK: Cloud Run ${SERVICE} Ready (${CR_URL})"
    CR_READY=1
  else
    note_issue "Cloud Run ${SERVICE} ei Ready"
  fi
else
  note_issue "Cloud Run ${SERVICE} puuttuu projektista ${GCP_PROJECT}"
fi

# --- LLM key ---
LLM_PLACEHOLDER=0
if gcloud secrets describe hermes-llm-api-key --project="${GCP_PROJECT}" &>/dev/null; then
  LLM="$(gcloud secrets versions access latest --secret=hermes-llm-api-key --project="${GCP_PROJECT}" 2>/dev/null || true)"
  if [[ -z "${LLM}" || "${LLM}" == REPLACE_WITH_* ]]; then
    note_issue "hermes-llm-api-key on placeholder — aseta OPENROUTER_API_KEY GitHub secretiin"
    LLM_PLACEHOLDER=1
  else
    echo "OK: hermes-llm-api-key asetettu"
  fi
else
  note_issue "hermes-llm-api-key secret puuttuu"
  LLM_PLACEHOLDER=1
fi

# --- Pub/Sub topic IAM ---
if gcloud pubsub topics describe "${TOPIC}" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "OK: topic ${TOPIC}"
  if gcloud pubsub topics get-iam-policy "${TOPIC}" --project="${GCP_PROJECT}" \
    --format=json 2>/dev/null | grep -q 'chat-api-push@system.gserviceaccount.com'; then
    echo "OK: chat-api-push publisher"
  else
    note_issue "chat-api-push@system.gserviceaccount.com ei publisher topicilla ${TOPIC}"
  fi
else
  note_issue "Pub/Sub topic ${TOPIC} puuttuu"
fi

# --- Subscription ---
if gcloud pubsub subscriptions describe "${SUB}" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "OK: subscription ${SUB}"
  UNDEL="$(gcloud pubsub subscriptions describe "${SUB}" --project="${GCP_PROJECT}" \
    --format='value(numUndeliveredMessages)' 2>/dev/null || echo "?")"
  echo "    undelivered (approx): ${UNDEL}"
else
  note_issue "Pub/Sub subscription ${SUB} puuttuu"
fi

# --- Korjaukset ---
if [[ "${APPLY}" == "1" ]]; then
  section "Korjaukset (--apply)"

  if [[ "${#ISSUES[@]}" -gt 0 ]]; then
    echo ">> infra/setup_gcp.sh (Pub/Sub IAM + secrets)"
    GCP_PROJECT="${GCP_PROJECT}" HERMES_CHAT_TRANSPORT=pubsub bash "${ROOT}/infra/setup_gcp.sh" || true
    note_fixed "setup_gcp.sh ajettu"
  fi

  if [[ "${CR_READY}" == "0" && "${GATEWAY_HOST}" == "cloudrun" ]]; then
    echo ">> deploy_pubsub_cloudrun.sh"
    if bash "${ROOT}/scripts/deploy_pubsub_cloudrun.sh"; then
      note_fixed "Cloud Run deploy"
      CR_READY=1
    else
      note_issue "Cloud Run deploy epäonnistui"
    fi
  fi

  if [[ "${CR_READY}" == "1" ]]; then
    echo ">> publish_chat_inbound_test.sh"
    EMAIL="${EMAIL:-opendoorsfinland@gmail.com}"
    TEXT="Self-heal test $(date -u +%H:%M:%S)"
    export EMAIL TEXT
    if bash "${ROOT}/scripts/publish_chat_inbound_test.sh"; then
      note_fixed "test-viesti julkaistu topicille"
    fi
  fi
fi

section "Yhteenveto"
echo "Gateway host: ${GATEWAY_HOST}"
echo "Cloud Run:    ${CR_URL:-ei käytössä / ei valmis}"
echo "Subscription: ${SUB_FULL}"
echo "Ongelmia:     ${#ISSUES[@]}"
echo "Korjauksia:   ${#FIXED[@]}"
if [[ "${#ISSUES[@]}" -gt 0 ]]; then
  printf '  - %s\n' "${ISSUES[@]}"
fi

# LLM placeholder ei estä infran valmiutta, mutta estää vastaukset
if [[ "${#ISSUES[@]}" -eq 0 ]]; then
  echo ""
  echo "OK — yhteys infra näyttää kunnossa"
  [[ "${LLM_PLACEHOLDER}" == "1" ]] && echo "HUOM: LLM-avain puuttuu → botti ei vastaa ennen OPENROUTER_API_KEY"
  exit 0
fi

# Jos vain LLM placeholder, infra voi olla OK
if [[ "${#ISSUES[@]}" -eq 1 && "${LLM_PLACEHOLDER}" == "1" && "${CR_READY}" == "1" ]]; then
  echo ""
  echo "OK — gateway käynnissä, LLM-avain odottaa"
  exit 0
fi

exit 1
