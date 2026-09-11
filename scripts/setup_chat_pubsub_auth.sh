#!/usr/bin/env bash
# Pub/Sub gateway auth — SA JSON Secret Managerista tai ADC impersonation.
# ÄLÄ kutsu setup_chat_outbound_auth.sh Pub/Sub-moodissa (se poistaa inbound-credentiaalit).
#
#   bash scripts/setup_chat_pubsub_auth.sh [ipad]
set -euo pipefail

TENANT="${1:-ipad}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
ENV_FILE="${HERMES_HOME}/.env"
DEST="${HERMES_HOME}/secrets/google-chat-sa.json"

# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/scripts/lib/tenant.sh"
load_tenant "${TENANT}"

SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
mkdir -p "${HERMES_HOME}/secrets" "${HERMES_HOME}/logs"
chmod 700 "${HERMES_HOME}/secrets" 2>/dev/null || true

echo "==> setup_chat_pubsub_auth: ${SA_EMAIL}"

if [[ -f "${ENV_FILE}" ]]; then
  python3 "${ROOT}/scripts/lib/strip_http_chat_env.py" "${ENV_FILE}" || true
fi

patch_env_key() {
  local key="$1" val="$2"
  [[ -f "${ENV_FILE}" ]] || touch "${ENV_FILE}"
  python3 - "${ENV_FILE}" "${key}" "${val}" <<'PY'
import pathlib, re, sys
path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
text = pathlib.Path(path).read_text(encoding="utf-8")
if re.search(rf"^{key}=", text, flags=re.M):
    text = re.sub(rf"^{key}=.*$", f"{key}={val}", text, count=1, flags=re.M)
else:
    text = text.rstrip() + f"\n{key}={val}\n"
pathlib.Path(path).write_text(text, encoding="utf-8")
PY
}

AUTH_MODE=""

if bash "${ROOT}/scripts/fetch_sa_to_path.sh" "${DEST}" "${GCP_PROJECT}" 2>/dev/null; then
  AUTH_MODE="sa-json-secret"
  patch_env_key "GOOGLE_CHAT_SERVICE_ACCOUNT_JSON" "${DEST}"
  patch_env_key "GOOGLE_APPLICATION_CREDENTIALS" "${DEST}"
  echo "OK: SA JSON Secret Managerista → ${DEST}"
elif [[ -f "${DEST}" ]] && [[ -s "${DEST}" ]]; then
  AUTH_MODE="sa-json-local"
  patch_env_key "GOOGLE_CHAT_SERVICE_ACCOUNT_JSON" "${DEST}"
  patch_env_key "GOOGLE_APPLICATION_CREDENTIALS" "${DEST}"
  echo "OK: käytetään olemassa olevaa ${DEST}"
elif bash "${ROOT}/scripts/ensure_tenant_sa.sh" "${TENANT}" 2>/dev/null && [[ -s "${DEST}" ]]; then
  AUTH_MODE="sa-json-artifact"
  patch_env_key "GOOGLE_CHAT_SERVICE_ACCOUNT_JSON" "${DEST}"
  patch_env_key "GOOGLE_APPLICATION_CREDENTIALS" "${DEST}"
  echo "OK: SA JSON ensure_tenant_sa → ${DEST}"
else
  echo "==> SA JSON ei saatavilla — yritetään ADC impersonation"
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "VIRHE: tarvitaan gcloud auth login TAI Secret Manager SA JSON" >&2
    exit 1
  fi
  if ! gcloud auth print-access-token >/dev/null 2>&1; then
    echo "VIRHE: gcloud ei kirjautunut — aja: gcloud auth login" >&2
    exit 1
  fi
  if ! gcloud auth print-access-token --impersonate-service-account="${SA_EMAIL}" >/dev/null 2>&1; then
    echo "VIRHE: impersonation epäonnistui — tarvitset Owner + tokenCreator ${SA_EMAIL}" >&2
    exit 1
  fi
  AUTH_MODE="adc-impersonation"
  patch_env_key "GOOGLE_CHAT_IMPERSONATE_SERVICE_ACCOUNT" "${SA_EMAIL}"
  patch_env_key "GOOGLE_CHAT_OUTBOUND_AUTH" "adc-impersonation"
  python3 - "${ENV_FILE}" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
keys = ("GOOGLE_CHAT_SERVICE_ACCOUNT_JSON", "GOOGLE_APPLICATION_CREDENTIALS")
text = path.read_text(encoding="utf-8")
for key in keys:
    text = re.sub(rf"^{key}=.*\n", "", text, flags=re.M)
path.write_text(text.rstrip() + "\n", encoding="utf-8")
PY
  echo "OK: ADC impersonation → ${SA_EMAIL}"
fi

MARKER="# --- Pub/Sub gateway auth ---"
if [[ -f "${ENV_FILE}" ]] && grep -qF "${MARKER}" "${ENV_FILE}"; then
  sed -i.bak "/${MARKER}/,/# --- end pubsub auth ---/d" "${ENV_FILE}" 2>/dev/null || true
fi
cat >> "${ENV_FILE}" <<EOF

${MARKER}
GOOGLE_CHAT_PUBSUB_AUTH=${AUTH_MODE}
# --- end pubsub auth ---
EOF
chmod 600 "${ENV_FILE}" 2>/dev/null || true
echo "OK: pubsub auth mode=${AUTH_MODE}"
