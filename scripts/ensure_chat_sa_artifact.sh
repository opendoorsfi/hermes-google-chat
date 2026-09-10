#!/usr/bin/env bash
# Tenant-artefaktiin SA JSON — Secret Manager tai uusi avain (GitHub Actions).
set -euo pipefail

TENANT="${1:?Usage: ensure_chat_sa_artifact.sh TENANT}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/scripts/lib/tenant.sh"
load_tenant "${TENANT}"

OUT="${ROOT}/out/tenants/${TENANT}/hermes-chat-bot-sa.json"
mkdir -p "$(dirname "${OUT}")"

if bash "${ROOT}/scripts/fetch_sa_to_path.sh" "${OUT}" "${GCP_PROJECT}"; then
  exit 0
fi

SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
if gcloud iam service-accounts keys create "${OUT}" \
  --iam-account="${SA_EMAIL}" \
  --project="${GCP_PROJECT}" 2>/tmp/hermes_tenant_sa.err; then
  chmod 600 "${OUT}"
  echo "OK: luotiin avain → ${OUT}"
  exit 0
fi

echo "VAROITUS: SA JSON ei saatu tenantille ${TENANT}" >&2
sed 's/^/  /' /tmp/hermes_tenant_sa.err >&2 || true
rm -f /tmp/hermes_tenant_sa.err "${OUT}"
exit 0
