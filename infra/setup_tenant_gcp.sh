#!/usr/bin/env bash
# GCP infra for one Hermes Chat tenant (HTTP + Funnel — no Pub/Sub).
#
#   TENANT=alice bash infra/setup_tenant_gcp.sh
#   # or
#   GCP_PROJECT=hermes-alice CHAT_HTTP_EVENTS_URL=https://... bash infra/setup_tenant_gcp.sh
#
# Ympäristömuuttujat GCP_PROJECT ja FUNNEL_BASE_URL ylikirjoittavat manifestin arvot
# (GitHub Actions: manifestit ovat gitignoressa, vain *.env.example on repossa).
# SKIP_SA_KEY=1 → ei luoda SA JSON -avainta (CI: avain luodaan Consolesta hostille).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/scripts/lib/tenant.sh"

TENANT="${TENANT:-}"
GCP_PROJECT_OVERRIDE="${GCP_PROJECT:-}"
FUNNEL_BASE_URL_OVERRIDE="${FUNNEL_BASE_URL:-}"
if [[ -n "${TENANT}" ]]; then
  load_tenant "${TENANT}"
  GCP_PROJECT="${GCP_PROJECT_OVERRIDE:-${GCP_PROJECT:?}}"
  FUNNEL_BASE_URL="${FUNNEL_BASE_URL_OVERRIDE:-${FUNNEL_BASE_URL:-}}"
  if [[ -z "${CHAT_HTTP_EVENTS_URL:-}" && "${FUNNEL_BASE_URL}" == *tailXXXX* ]]; then
    if [[ "${ALLOW_PLACEHOLDER_FUNNEL:-0}" == "1" ]]; then
      echo "VAROITUS: FUNNEL_BASE_URL on placeholder — GCP-resurssit luodaan, Chat Console odottaa oikeaa URL:ia."
    else
      echo "VIRHE: FUNNEL_BASE_URL on placeholder (${FUNNEL_BASE_URL})."
      echo "  Kopioi config/tenants/${TENANT}.env.example → ${TENANT}.env ja aseta oikea Funnel-URL,"
      echo "  tai anna FUNNEL_BASE_URL=https://<host>.ts.net ympäristömuuttujana."
      exit 1
    fi
  fi
  CHAT_HTTP_EVENTS_URL="${CHAT_HTTP_EVENTS_URL:-$(tenant_chat_http_url)}"
fi

GCP_PROJECT="${GCP_PROJECT:-}"
CHAT_HTTP_EVENTS_URL="${CHAT_HTTP_EVENTS_URL:-}"
SA_NAME="${SA_NAME:-hermes-chat-bot}"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"

if [[ -z "${GCP_PROJECT}" ]]; then
  echo "VIRHE: aseta TENANT=... tai GCP_PROJECT=..."
  exit 1
fi
if [[ -z "${CHAT_HTTP_EVENTS_URL}" ]]; then
  echo "VIRHE: CHAT_HTTP_EVENTS_URL puuttuu (tai TENANT + FUNNEL_BASE_URL manifestissa)"
  exit 1
fi

echo "==> Tenant GCP setup: project=${GCP_PROJECT}"
echo "    HTTP endpoint: ${CHAT_HTTP_EVENTS_URL}"

enable_apis() {
  local apis="$1"
  if gcloud services enable ${apis} --project="${GCP_PROJECT}" 2>/tmp/hermes_tenant_enable.err; then
    return 0
  fi
  echo "VAROITUS: gcloud services enable epäonnistui (API:t voivat olla jo päällä)."
  sed 's/^/  /' /tmp/hermes_tenant_enable.err || true
  rm -f /tmp/hermes_tenant_enable.err
  return 0
}

echo "==> Enable APIs (Chat + IAM only)"
enable_apis "chat.googleapis.com iam.googleapis.com"

if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "OK: service account ${SA_EMAIL} exists"
elif gcloud iam service-accounts create "${SA_NAME}" \
  --project="${GCP_PROJECT}" \
  --display-name="Hermes Google Chat (${TENANT:-tenant})" 2>/tmp/hermes_sa_create.err; then
  echo "OK: created ${SA_EMAIL}"
else
  echo "VAROITUS: SA ${SA_EMAIL} puuttuu eikä luonti onnistunut (deploy-SA IAM?)."
  echo "  Anna github-azuracast-deploy@od-azuracast-sync.iam.gserviceaccount.com:"
  echo "    roles/serviceusage.serviceUsageAdmin + roles/iam.serviceAccountAdmin"
  sed 's/^/  /' /tmp/hermes_sa_create.err || true
  rm -f /tmp/hermes_sa_create.err
fi

OUT_DIR="${ROOT}/out/tenants/${TENANT:-${GCP_PROJECT}}"
mkdir -p "${OUT_DIR}"

KEY_PATH="${OUT_DIR}/hermes-chat-bot-sa.json"
if [[ "${SKIP_SA_KEY:-0}" == "1" ]]; then
  echo "==> SKIP_SA_KEY=1 — SA JSON -avainta ei luoda CI:ssä."
  echo "  Host hakee avaimen: scripts/ensure_tenant_sa.sh (gh artifact / Secret Manager / gcloud)"
elif [[ ! -f "${KEY_PATH}" ]]; then
  echo "==> Yritetään SA JSON -avain (host hakee automaattisesti — ei Console-latausta)"
  if gcloud iam service-accounts keys create "${KEY_PATH}" \
    --iam-account="${SA_EMAIL}" \
    --project="${GCP_PROJECT}" 2>/tmp/hermes_tenant_key.err; then
    chmod 600 "${KEY_PATH}"
    echo "OK: ${KEY_PATH}"
  else
    echo "VAROITUS: SA-avain epäonnistui (deploy-SA IAM / org policy)."
    echo "  Anna github-azuracast-deploy@od-azuracast-sync.iam.gserviceaccount.com:"
    echo "    roles/iam.serviceAccountKeyAdmin (tai serviceAccountAdmin)"
    sed 's/^/  /' /tmp/hermes_tenant_key.err || true
    rm -f /tmp/hermes_tenant_key.err
  fi
fi

if [[ -f "${KEY_PATH}" && -s "${KEY_PATH}" && "${TENANT:-}" != "" ]]; then
  SECRET_NAME="hermes-chat-sa-${TENANT}"
  echo "==> Secret Manager: ${SECRET_NAME}"
  if ! gcloud secrets describe "${SECRET_NAME}" --project="${GCP_PROJECT}" &>/dev/null; then
    gcloud secrets create "${SECRET_NAME}" \
      --replication-policy=automatic \
      --project="${GCP_PROJECT}" 2>/tmp/hermes_secret_create.err || {
      echo "VAROITUS: Secret Manager -luonti epäonnistui"
      sed 's/^/  /' /tmp/hermes_secret_create.err || true
      rm -f /tmp/hermes_secret_create.err
    }
  fi
  if gcloud secrets describe "${SECRET_NAME}" --project="${GCP_PROJECT}" &>/dev/null; then
    gcloud secrets versions add "${SECRET_NAME}" \
      --data-file="${KEY_PATH}" \
      --project="${GCP_PROJECT}" 2>/tmp/hermes_secret_add.err && \
      echo "OK: ${SECRET_NAME} (host: gcloud secrets versions access / gh artifact)" || {
      echo "VAROITUS: Secret Manager -versio epäonnistui"
      sed 's/^/  /' /tmp/hermes_secret_add.err || true
      rm -f /tmp/hermes_secret_add.err
    }
  fi
fi

cat > "${OUT_DIR}/gcp.env" <<EOF
GCP_PROJECT=${GCP_PROJECT}
SA_EMAIL=${SA_EMAIL}
CHAT_HTTP_EVENTS_URL=${CHAT_HTTP_EVENTS_URL}
TENANT=${TENANT:-}
EOF
chmod 600 "${OUT_DIR}/gcp.env"

cat > "${OUT_DIR}/CHAT_CONSOLE_CHECKLIST.md" <<EOF
# Chat API Console — ${GCP_PROJECT}

1. APIs & Services → **Google Chat API** → **Configuration**
2. **App status:** Live (tai Testing + testaajat)
3. **App name:** ${CHAT_APP_DISPLAY_NAME:-Hermes}
4. **Functionality:** Receive 1:1 messages + Join spaces and group conversations
5. **Connection settings:** HTTP endpoint URL
6. **URL:** \`${CHAT_HTTP_EVENTS_URL}\`
7. **Visibility:** Specific people → ${GOOGLE_CHAT_ALLOWED_USERS:-your@email}
8. Save

Install bot in Chat (DM for personal, space for team).
EOF

echo ""
echo "OK — tenant GCP valmis."
echo "  Artefaktit: ${OUT_DIR}/"
echo "  Seuraavaksi: Chat Console (ks. CHAT_CONSOLE_CHECKLIST.md)"
echo "  Host: bash scripts/install_hermes_host.sh --tenant ${TENANT:-<tenant>}"
