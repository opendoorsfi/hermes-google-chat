#!/usr/bin/env bash
# Anna registry-käyttäjille oikeus impersonoida hermes-chat-bot SA:ta (ei JSON-avaimia).
# Org policy: constraints/iam.disableServiceAccountKeyCreation estää keys.create.
#
#   bash infra/grant_chat_sa_impersonation.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GCP_PROJECT="${GCP_PROJECT:-od-kansiot}"
SA_NAME="${SA_NAME:-hermes-chat-bot}"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"

mapfile -t USERS < <(python3 "${ROOT}/scripts/chat_registry.py" hub-json | python3 -c "
import json, sys
h = json.load(sys.stdin)
for e in h.get('allowed_users', '').replace(' ', '').split(','):
    if e.strip():
        print(e.strip().lower())
")

if [[ ${#USERS[@]} -eq 0 ]]; then
  echo "VAROITUS: ei käyttäjiä registryssä"
  exit 0
fi

echo "==> Grant serviceAccountTokenCreator → ${SA_EMAIL}"
for email in "${USERS[@]}"; do
  echo "  user:${email}"
  gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
    --project="${GCP_PROJECT}" \
    --member="user:${email}" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --quiet >/dev/null 2>/tmp/hermes_imp_grant.err || {
    echo "VAROITUS: tokenCreator epäonnistui user:${email}"
    sed 's/^/    /' /tmp/hermes_imp_grant.err 2>/dev/null || true
  }
done
rm -f /tmp/hermes_imp_grant.err
echo "OK — outbound: gcloud auth application-default login --impersonate-service-account=${SA_EMAIL}"
