#!/usr/bin/env bash
# Varmista hermes-chat-bot SA + JSON Secret Managerissa (GitHub Actions WIF).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GCP_PROJECT="${GCP_PROJECT:-$(python3 "${ROOT}/scripts/chat_registry.py" hub-json | python3 -c "import json,sys; print(json.load(sys.stdin)['gcp_project'])")}"
SA_NAME="${SA_NAME:-hermes-chat-bot}"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
SECRET="hermes-google-chat-sa-json"

if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${GCP_PROJECT}" >/dev/null 2>&1; then
  echo "==> Luodaan SA ${SA_EMAIL}"
  gcloud iam service-accounts create "${SA_NAME}" \
    --project="${GCP_PROJECT}" \
    --display-name="Hermes Google Chat Bot"
fi

if gcloud secrets describe "${SECRET}" --project="${GCP_PROJECT}" >/dev/null 2>&1; then
  echo "OK: ${SECRET} on jo Secret Managerissa"
  exit 0
fi

TMPKEY="$(mktemp)"
if ! gcloud iam service-accounts keys create "${TMPKEY}" \
  --iam-account="${SA_EMAIL}" \
  --project="${GCP_PROJECT}" 2>/tmp/hermes_sa_key.err; then
  echo "VAROITUS: SA-avainta ei voitu luoda (org policy?):" >&2
  sed 's/^/  /' /tmp/hermes_sa_key.err >&2 || true
  rm -f "${TMPKEY}" /tmp/hermes_sa_key.err
  exit 0
fi
rm -f /tmp/hermes_sa_key.err

gcloud secrets create "${SECRET}" --data-file="${TMPKEY}" --project="${GCP_PROJECT}"
gcloud secrets add-iam-policy-binding "${SECRET}" \
  --project="${GCP_PROJECT}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet >/dev/null || true
rm -f "${TMPKEY}"
echo "OK: ${SECRET} luotu"
