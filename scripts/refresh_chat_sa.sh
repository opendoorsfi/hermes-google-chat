#!/usr/bin/env bash
# Uusi hermes-chat-bot SA-avain + päivitä ~/.hermes/.env + käynnistä gateway.
#
# Outbound (vastaus Chatissa) vaatii SA JSON:n — ADC (gcloud user login) EI riitä.
#
#   bash scripts/refresh_chat_sa.sh [natalia]
#   bash scripts/refresh_chat_sa.sh natalia --restart
set -euo pipefail

TENANT="${1:-natalia}"
DO_RESTART=0
[[ "${2:-}" == "--restart" ]] && DO_RESTART=1

ROOT="$(cd "$(dirname "$0")" && pwd)"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
ENV_FILE="${HERMES_HOME}/.env"
DEST="${HERMES_HOME}/secrets/google-chat-sa.json"

echo "==> refresh_chat_sa: tenant=${TENANT}"

echo "--- ADC (informatiivinen; outbound ei käytä tätä suoraan) ---"
if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "ADC: OK (gcloud application-default)"
else
  echo "ADC: ei käytössä — tarvitaan gcloud auth application-default login TAI SA JSON alla"
fi
if gcloud auth print-access-token >/dev/null 2>&1; then
  echo "gcloud user: OK"
else
  echo "gcloud user: ei kirjautunut (gcloud auth login auttaa avaimen luonnissa)"
fi

echo ""
echo "--- SA JSON (pakollinen outboundille) ---"
export TENANT
bash "${ROOT}/ensure_tenant_sa.sh" "${TENANT}" --force

mkdir -p "${HERMES_HOME}/secrets"
SA_PATH="${DEST}"
for key in GOOGLE_CHAT_SERVICE_ACCOUNT_JSON GOOGLE_APPLICATION_CREDENTIALS; do
  if [[ -f "${ENV_FILE}" ]] && grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
    # shellcheck disable=SC2016
    python3 - "${ENV_FILE}" "${key}" "${SA_PATH}" <<'PY'
import pathlib, re, sys
path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
text = pathlib.Path(path).read_text(encoding="utf-8")
text = re.sub(rf"^{key}=.*$", f"{key}={val}", text, count=1, flags=re.M)
pathlib.Path(path).write_text(text, encoding="utf-8")
print(f"päivitetty {key}")
PY
  else
    echo "${key}=${SA_PATH}" >> "${ENV_FILE}"
    echo "lisätty ${key}"
  fi
done
chmod 600 "${ENV_FILE}" 2>/dev/null || true

echo ""
echo "OK: outbound SA → ${SA_PATH}"
if [[ "${DO_RESTART}" == "1" ]] || [[ "$(uname -s)" == "Darwin" ]]; then
  PORT="$(python3 "${ROOT}/chat_registry.py" host-users natalia-mac 2>/dev/null | python3 -c "import json,sys; u=json.load(sys.stdin); print(u[0]['PORT'])" 2>/dev/null || echo 8642)"
  bash "${ROOT}/ensure_mac_gateway_running.sh" "${PORT}" --restart 2>/dev/null || hermes gateway restart 2>/dev/null || true
fi
echo "Testaa: uusi viesti Google Chatissa → botin pitäisi vastata."
