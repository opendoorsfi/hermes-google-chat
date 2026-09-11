#!/usr/bin/env bash
# One-shot GCP infra for hermes-google-chat.
#
# Default: Pub/Sub Chat inbound (Hermes official guide).
#   export GCP_PROJECT=od-kansiot
#   export GCP_REGION=europe-north1
#   bash infra/setup_gcp.sh
#
# HTTP (vain jos org estää chat-api-push IAM):
#   export HERMES_CHAT_TRANSPORT=http
#   bash infra/setup_gcp.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
GCP_REGION="${GCP_REGION:-europe-north1}"
HERMES_CHAT_TRANSPORT="${HERMES_CHAT_TRANSPORT:-pubsub}"
SA_NAME="${SA_NAME:-hermes-chat-bot}"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
TOPIC="${TOPIC:-hermes-chat-events}"
SUB="${SUB:-hermes-chat-events-sub}"
CHAT_PUSH_SA="chat-api-push@system.gserviceaccount.com"
AR_REPO="${AR_REPO:-hermes-google-chat}"

if [[ -z "${GCP_PROJECT}" || "${GCP_PROJECT}" == "(unset)" ]]; then
  echo "VIRHE: aseta GCP_PROJECT"
  exit 1
fi

echo "==> Projekti: ${GCP_PROJECT} / ${GCP_REGION} (transport=${HERMES_CHAT_TRANSPORT})"

enable_apis() {
  local apis="$1"
  if gcloud services enable ${apis} --project="${GCP_PROJECT}" 2>/tmp/hermes_enable.err; then
    return 0
  fi
  echo "VAROITUS: gcloud services enable epäonnistui (API:t voivat olla jo päällä tai ei enable-oikeutta)."
  sed 's/^/  /' /tmp/hermes_enable.err || true
  rm -f /tmp/hermes_enable.err
  return 0
}

APIS="run.googleapis.com secretmanager.googleapis.com artifactregistry.googleapis.com chat.googleapis.com iam.googleapis.com iamcredentials.googleapis.com cloudresourcemanager.googleapis.com cloudbuild.googleapis.com"
if [[ "${HERMES_CHAT_TRANSPORT}" == "pubsub" ]]; then
  APIS="${APIS} pubsub.googleapis.com"
fi
echo "==> Enable APIs (best-effort)"
enable_apis "${APIS}"

if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${GCP_PROJECT}" &>/dev/null; then
  gcloud iam service-accounts create "${SA_NAME}" \
    --project="${GCP_PROJECT}" \
    --display-name="Hermes Google Chat Bot"
fi

if [[ "${HERMES_CHAT_TRANSPORT}" == "pubsub" ]]; then
  if ! gcloud pubsub topics describe "${TOPIC}" --project="${GCP_PROJECT}" &>/dev/null; then
    gcloud pubsub topics create "${TOPIC}" --project="${GCP_PROJECT}"
  fi

  if ! gcloud pubsub subscriptions describe "${SUB}" --project="${GCP_PROJECT}" &>/dev/null; then
    gcloud pubsub subscriptions create "${SUB}" \
      --project="${GCP_PROJECT}" \
      --topic="${TOPIC}" \
      --ack-deadline=60 \
      --message-retention-duration=7d
  fi

  echo "==> IAM topic: ${CHAT_PUSH_SA} → publisher"
  if ! gcloud pubsub topics add-iam-policy-binding "${TOPIC}" \
    --project="${GCP_PROJECT}" \
    --member="serviceAccount:${CHAT_PUSH_SA}" \
    --role="roles/pubsub.publisher" \
    --quiet 2>/tmp/hermes_chat_push_iam.err; then
    echo ""
    echo "VAROITUS: Chat Pub/Sub publisher -IAM epäonnistui (org policy?)."
    echo "  Tarkista org policy: chat-api-push@system.gserviceaccount.com → roles/pubsub.publisher topicilla"
    sed 's/^/  /' /tmp/hermes_chat_push_iam.err || true
    echo ""
  fi
  rm -f /tmp/hermes_chat_push_iam.err

  echo "==> IAM subscription: ${SA_EMAIL} → subscriber + viewer"
  gcloud pubsub subscriptions add-iam-policy-binding "${SUB}" \
    --project="${GCP_PROJECT}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/pubsub.subscriber" \
    --quiet

  gcloud pubsub subscriptions add-iam-policy-binding "${SUB}" \
    --project="${GCP_PROJECT}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/pubsub.viewer" \
    --quiet
else
  echo "==> HTTP-moodi: Pub/Sub topic/sub ohitetaan (ei chat-api-push IAM -vaatimusta)"
fi

upsert_secret() {
  local name="$1"
  local value="$2"
  if gcloud secrets describe "${name}" --project="${GCP_PROJECT}" &>/dev/null; then
    printf '%s' "${value}" | gcloud secrets versions add "${name}" --data-file=- --project="${GCP_PROJECT}"
  else
    printf '%s' "${value}" | gcloud secrets create "${name}" --data-file=- --project="${GCP_PROJECT}"
  fi
}

if [[ -z "${WEBHOOK_PLACEHOLDER:-}" ]]; then
  if ! gcloud secrets describe "hermes-llm-api-key" --project="${GCP_PROJECT}" &>/dev/null; then
    upsert_secret "hermes-llm-api-key" "REPLACE_WITH_OPENROUTER_OR_OPENAI_KEY"
  else
    echo "==> hermes-llm-api-key on jo olemassa — ei ylikirjoiteta"
  fi
fi

if ! gcloud secrets describe "hermes-api-server-key" --project="${GCP_PROJECT}" &>/dev/null; then
  upsert_secret "hermes-api-server-key" "$(openssl rand -hex 32)"
fi

if ! gcloud secrets describe "hermes-google-chat-sa-json" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "==> Yritetään SA-avain Secret Manageriin (valinnainen)..."
  TMPKEY="$(mktemp)"
  if gcloud iam service-accounts keys create "${TMPKEY}" \
    --iam-account="${SA_EMAIL}" \
    --project="${GCP_PROJECT}" 2>/tmp/hermes_sa_key.err; then
    gcloud secrets create "hermes-google-chat-sa-json" \
      --data-file="${TMPKEY}" \
      --project="${GCP_PROJECT}"
  else
    echo "  OK: käytetään Cloud Run attached SA:ta (ei JSON-avainta)."
  fi
  rm -f "${TMPKEY}" /tmp/hermes_sa_key.err
fi

for secret in hermes-google-chat-sa-json hermes-llm-api-key hermes-api-server-key; do
  if gcloud secrets describe "${secret}" --project="${GCP_PROJECT}" &>/dev/null; then
    gcloud secrets add-iam-policy-binding "${secret}" \
      --project="${GCP_PROJECT}" \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="roles/secretmanager.secretAccessor" \
      --quiet >/dev/null || true
  fi
done

if ! gcloud artifacts repositories describe "${AR_REPO}" \
  --location="${GCP_REGION}" --project="${GCP_PROJECT}" &>/dev/null; then
  gcloud artifacts repositories create "${AR_REPO}" \
    --project="${GCP_PROJECT}" \
    --location="${GCP_REGION}" \
    --repository-format=docker \
    --description="Hermes Google Chat container images"
fi

mkdir -p "${ROOT}/out"
cat > "${ROOT}/out/gcp_setup.env" <<EOF
GCP_PROJECT=${GCP_PROJECT}
GCP_REGION=${GCP_REGION}
SA_EMAIL=${SA_EMAIL}
HERMES_CHAT_TRANSPORT=${HERMES_CHAT_TRANSPORT}
ARTIFACT_REGISTRY=${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${AR_REPO}
EOF
chmod 600 "${ROOT}/out/gcp_setup.env"

echo ""
echo "OK — infra valmis (transport=${HERMES_CHAT_TRANSPORT})."
echo "  SA: ${SA_EMAIL}"
echo ""
if [[ "${HERMES_CHAT_TRANSPORT}" == "http" ]]; then
  echo "Seuraavaksi:"
  echo "  1. bash deploy/cloudrun/deploy.sh"
  echo "  2. Chat API → HTTP endpoint URL = out/deploy.env → CHAT_HTTP_EVENTS_URL"
  echo "  3. Katso infra/chat_api_config.md"
else
  echo "Seuraavaksi:"
  echo "  1. Chat API → Pub/Sub → projects/${GCP_PROJECT}/topics/${TOPIC}"
  echo "  2. bash deploy/cloudrun/deploy.sh (HERMES_CHAT_TRANSPORT=pubsub)"
fi
