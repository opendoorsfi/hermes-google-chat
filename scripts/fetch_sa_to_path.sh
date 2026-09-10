#!/usr/bin/env bash
# Fetch Chat SA JSON to a path — Secret Manager, no manual download.
#   bash scripts/fetch_sa_to_path.sh OUT_PATH [GCP_PROJECT]
set -euo pipefail

DEST="${1:?Usage: fetch_sa_to_path.sh OUT_PATH [GCP_PROJECT]}"
GCP_PROJECT="${2:-od-azuracast-sync}"
TENANT="${TENANT:-}"

mkdir -p "$(dirname "${DEST}")"

try_secret() {
  local secret="$1"
  gcloud secrets describe "${secret}" --project="${GCP_PROJECT}" >/dev/null 2>&1 || return 1
  gcloud secrets versions access latest \
    --secret="${secret}" \
    --project="${GCP_PROJECT}" > "${DEST}"
  [[ -s "${DEST}" ]]
}

SECRETS=(hermes-google-chat-sa-json)
if [[ -n "${TENANT}" ]]; then
  SECRETS+=( "hermes-chat-sa-${TENANT}" )
fi

for secret in "${SECRETS[@]}"; do
  if try_secret "${secret}"; then
    chmod 600 "${DEST}"
    echo "OK: ${secret} → ${DEST}"
    exit 0
  fi
  rm -f "${DEST}"
done

echo "fetch_sa_to_path: ei löytynyt Secret Managerista (project=${GCP_PROJECT})" >&2
exit 1
