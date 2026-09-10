#!/usr/bin/env bash
# Ensure tenant Chat SA JSON exists locally — no manual Console download.
#
#   bash scripts/ensure_tenant_sa.sh natalia
#
# Sources (in order): existing file, CI artifact dir, GitHub Actions artifact (gh),
# GCP Secret Manager, gcloud keys create.
set -euo pipefail

TENANT="${1:?Usage: ensure_tenant_sa.sh TENANT}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/scripts/lib/tenant.sh"
load_tenant "${TENANT}"

SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
KEY_SRC="${ROOT}/out/tenants/${TENANT}/hermes-chat-bot-sa.json"

if [[ "$(uname -s)" == "Darwin" ]]; then
  SECRETS_DIR="${HERMES_HOME:-${HOME}/.hermes}/secrets"
else
  SECRETS_DIR="${HERMES_SECRETS_DIR:-/home/${LINUX_USER}/.hermes/secrets}"
fi
DEST="${SECRETS_DIR}/google-chat-sa.json"

mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}" 2>/dev/null || true

install_key() {
  local src="$1"
  cp "${src}" "${DEST}"
  chmod 600 "${DEST}"
  echo "OK: SA → ${DEST}"
}

if [[ -f "${DEST}" && -s "${DEST}" ]]; then
  echo "OK: SA jo olemassa ${DEST}"
  exit 0
fi
[[ -f "${DEST}" && ! -s "${DEST}" ]] && rm -f "${DEST}"

if [[ -f "${KEY_SRC}" && -s "${KEY_SRC}" ]]; then
  install_key "${KEY_SRC}"
  exit 0
fi
[[ -f "${KEY_SRC}" && ! -s "${KEY_SRC}" ]] && rm -f "${KEY_SRC}"

if bash "${ROOT}/scripts/fetch_sa_to_path.sh" "${DEST}" "${GCP_PROJECT}" 2>/dev/null; then
  exit 0
fi

create_sa_key_gcloud() {
  command -v gcloud >/dev/null 2>&1 || return 1
  if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${GCP_PROJECT}" >/dev/null 2>&1; then
    return 1
  fi
  if gcloud iam service-accounts keys create "${DEST}" \
    --iam-account="${SA_EMAIL}" \
    --project="${GCP_PROJECT}" 2>/tmp/hermes_ensure_sa.err; then
    chmod 600 "${DEST}"
    echo "OK: luotiin SA-avain gcloudilla → ${DEST}"
    return 0
  fi
  sed 's/^/  /' /tmp/hermes_ensure_sa.err 2>/dev/null || true
  rm -f /tmp/hermes_ensure_sa.err
  return 1
}

fetch_sa_from_github() {
  command -v gh >/dev/null 2>&1 || return 1
  gh auth status >/dev/null 2>&1 || return 1
  local repo="${GITHUB_REPOSITORY:-opendoorsfi/hermes-google-chat}"
  local run_id
  run_id="$(gh run list --repo "${repo}" --workflow=sync-chat-users.yml --status=success --limit 20 \
    --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  [[ -n "${run_id}" && "${run_id}" != "null" ]] || return 1
  local tmpdir
  tmpdir="$(mktemp -d)"
  if ! gh run download "${run_id}" -R "${repo}" -n "tenant-${TENANT}-gcp" -D "${tmpdir}" 2>/dev/null; then
    rm -rf "${tmpdir}"
    return 1
  fi
  local found
  found="$(find "${tmpdir}" -type f -name 'hermes-chat-bot-sa.json' -size +0c 2>/dev/null | head -1)"
  rm -rf "${tmpdir}"
  [[ -n "${found}" && -s "${found}" ]] || return 1
  install_key "${found}"
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  if create_sa_key_gcloud; then exit 0; fi
  if fetch_sa_from_github; then exit 0; fi
else
  if fetch_sa_from_github; then exit 0; fi
  if create_sa_key_gcloud; then exit 0; fi
fi

echo "VIRHE: SA JSON ei saatu automaattisesti tenantille ${TENANT}" >&2
echo "  Odota GitHub Sync Chat users -workflow (luo avaimen + Secret Manager)." >&2
echo "  Macilla: gcloud auth login (luo avain suoraan) tai gh auth login (lataa artefaktista)." >&2
exit 1
