#!/usr/bin/env bash
# Outbound Chat (vastaukset) ilman SA JSON -avainta — ADC + SA impersonation.
# od-kansiot org policy estää service account key -luonnin.
#
#   bash scripts/setup_chat_outbound_auth.sh [natalia] [--restart]
set -euo pipefail

TENANT="${1:-natalia}"
DO_RESTART=0
[[ "${2:-}" == "--restart" ]] && DO_RESTART=1

ROOT="$(cd "$(dirname "$0")" && pwd)"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
ENV_FILE="${HERMES_HOME}/.env"
DEST="${HERMES_HOME}/secrets/google-chat-sa.json"

# shellcheck source=scripts/lib/tenant.sh
source "${ROOT}/lib/tenant.sh"
load_tenant "${TENANT}"

SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"

echo "==> setup_chat_outbound_auth: ${SA_EMAIL}"

strip_sa_json_from_env() {
  [[ -f "${ENV_FILE}" ]] || return 0
  python3 - "${ENV_FILE}" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
keys = ("GOOGLE_CHAT_SERVICE_ACCOUNT_JSON", "GOOGLE_APPLICATION_CREDENTIALS")
text = path.read_text(encoding="utf-8")
for key in keys:
    text = re.sub(rf"^{key}=.*\n", "", text, flags=re.M)
path.write_text(text.rstrip() + "\n", encoding="utf-8")
print("OK: poistettu SA JSON -polut .env:stä (käytetään ADC impersonation)")
PY
}

if [[ -f "${DEST}" ]]; then
  if ! python3 - "${DEST}" "${SA_EMAIL}" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("client_email") == sys.argv[2]
PY
  then
    bak="${DEST}.bak.$(date +%s)"
    mv "${DEST}" "${bak}"
    echo "OK: vanha väärä SA JSON → ${bak}"
  else
    echo "VAROITUS: oikea SA JSON löytyy mutta org policy suosii impersonationia — siirretään sivuun"
    mv "${DEST}" "${DEST}.unused.$(date +%s)" 2>/dev/null || rm -f "${DEST}"
  fi
fi
strip_sa_json_from_env

if ! command -v gcloud >/dev/null 2>&1; then
  echo "VIRHE: gcloud puuttuu" >&2
  exit 1
fi
if ! gcloud auth print-access-token >/dev/null 2>&1; then
  echo "VIRHE: gcloud user ei kirjautunut (tarvitaan kerran interaktiivinen login hostilla)" >&2
  exit 1
fi

echo "--- testaa impersonation ---"
if ! gcloud auth print-access-token --impersonate-service-account="${SA_EMAIL}" >/dev/null 2>&1; then
  echo "VIRHE: impersonation epäonnistui — aja CI: infra/grant_chat_sa_impersonation.sh tai odota Sync Chat users" >&2
  exit 1
fi
echo "OK: gcloud impersonation → ${SA_EMAIL}"

# Päivitä ADC impersonoinnilla (ei-interaktiivinen jos user refresh token on olemassa)
if ! gcloud auth application-default print-access-token --impersonate-service-account="${SA_EMAIL}" >/dev/null 2>&1; then
  echo "==> Päivitetään ADC impersonoinnilla"
  gcloud auth application-default login \
    --impersonate-service-account="${SA_EMAIL}" \
    --quiet 2>/dev/null || \
  gcloud auth application-default login \
    --impersonate-service-account="${SA_EMAIL}" 2>/dev/null || true
fi

if ! gcloud auth application-default print-access-token --impersonate-service-account="${SA_EMAIL}" >/dev/null 2>&1; then
  echo "VIRHE: ADC impersonation ei toimi vielä" >&2
  exit 1
fi

MARKER="# --- Google Chat outbound (ADC impersonation) ---"
if [[ -f "${ENV_FILE}" ]] && grep -qF "${MARKER}" "${ENV_FILE}"; then
  sed -i.bak "/${MARKER}/,/# --- end outbound ---/d" "${ENV_FILE}" 2>/dev/null || true
fi
cat >> "${ENV_FILE}" <<EOF

${MARKER}
GOOGLE_CHAT_OUTBOUND_AUTH=adc-impersonation
GOOGLE_CHAT_IMPERSONATE_SERVICE_ACCOUNT=${SA_EMAIL}
# --- end outbound ---
EOF
chmod 600 "${ENV_FILE}" 2>/dev/null || true

# Hermes gateway lukee ADC:n — älä aseta GOOGLE_APPLICATION_CREDENTIALS vanhaan JSON:iin
export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="${SA_EMAIL}"

echo "OK: outbound auth = ADC impersonation (${SA_EMAIL})"

if [[ "${DO_RESTART}" == "1" ]] && command -v hermes >/dev/null 2>&1; then
  PORT="$(python3 "${ROOT}/chat_registry.py" host-users natalia-mac 2>/dev/null | python3 -c "import json,sys; u=json.load(sys.stdin); print(u[0]['PORT'])" 2>/dev/null || echo 8642)"
  CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="${SA_EMAIL}" \
    bash "${ROOT}/ensure_mac_gateway_running.sh" "${PORT}" --restart 2>/dev/null || \
    CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="${SA_EMAIL}" hermes gateway restart 2>/dev/null || true
fi
