#!/usr/bin/env bash
# Mac-host: Pub/Sub-moodissa gateway ajetaan work-h:llä — tämä vain riippuvuudet + outbound.
#
#   cd ~/hermes-google-chat && git pull && bash scripts/repair_mac_chat.sh
set -euo pipefail

EMAIL="${1:-natalia@info.opendoors.fi}"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
REPO="${HERMES_REPO_DIR:-}"

if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/bootstrap_hermes_mac.sh" ]]; then
  REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
elif [[ -z "${REPO}" ]]; then
  for d in "${HOME}/hermes-google-chat" "${HOME}/projects/hermes-google-chat"; do
    [[ -f "${d}/scripts/repair_mac_chat.sh" ]] && REPO="${d}" && break
  done
fi
if [[ -z "${REPO}" ]]; then
  REPO="$(mktemp -d)"
  git clone --depth 1 https://github.com/opendoorsfi/hermes-google-chat.git "${REPO}"
fi

cd "${REPO}"
git pull --ff-only 2>/dev/null || true

TRANSPORT="$(python3 -c "import json; print(json.load(open('config/tenants/registry.json'))['default_chat_transport'])")"
GATEWAY_HOST="$(python3 -c "
import sys
sys.path.insert(0, 'scripts')
from chat_registry import gateway_host_id, load_registry
print(gateway_host_id(load_registry()))
")"

TENANT="$(python3 -c "import re; e='${EMAIL}'.split('@')[0].lower(); print(re.sub(r'[^a-z0-9]+','-',e).strip('-'))")"
export TENANT

echo "==> repair_mac_chat: ${EMAIL} transport=${TRANSPORT}"

if [[ "${TRANSPORT}" == "pubsub" ]]; then
  echo "Pub/Sub: gateway ajetaan hostilla ${GATEWAY_HOST} — Mac ei pullaa subscriptionia."
  HERMES_PY=""
  for cand in /usr/local/lib/hermes-agent/venv/bin/python "${HOME}/.hermes/hermes-agent/venv/bin/python"; do
    [[ -n "${cand}" && -x "${cand}" ]] && HERMES_PY="${cand}" && break
  done
  if [[ -n "${HERMES_PY}" ]]; then
    HERMES_SRC="${HERMES_PY%/venv/bin/python*}"
    (cd "${HERMES_SRC}" && "${HERMES_PY}" -m plugins.platforms.google_chat.oauth --install-deps) \
      || "${HERMES_PY}" -m pip install --quiet google-cloud-pubsub google-api-python-client google-auth google-auth-oauthlib google-auth-httplib2 httplib2 \
      || true
  fi
  bash scripts/setup_chat_outbound_auth.sh "${TENANT}" --restart 2>/dev/null || true
  echo ""
  echo "OK — käytä Chatissa: Find apps → hermes-chat (gateway work-h:llä)."
  python3 scripts/chat_registry.py summary
  exit 0
fi

PORT="$(python3 scripts/chat_registry.py host-users natalia-mac 2>/dev/null | python3 -c "
import json, sys
users = json.load(sys.stdin)
print(users[0]['PORT'] if users else 8642)
" 2>/dev/null || echo 8642)"

python3 scripts/lib/strip_pubsub_env.py "${HOME}/.hermes/.env" 2>/dev/null || true
bash scripts/setup_chat_outbound_auth.sh "${TENANT}" --restart || echo "VAROITUS: outbound auth"
bash scripts/bootstrap_hermes_mac.sh "${EMAIL}" || true
bash scripts/ensure_mac_gateway_running.sh "${PORT}"

EVENTS="$(python3 scripts/chat_registry.py summary 2>/dev/null | awk -F'`' '/Chat HTTP URL/{print $2; exit}')"
FUNNEL_CODE="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${EVENTS}" \
  -H 'Content-Type: application/json' -d '{}' 2>/dev/null || echo 000)"

echo ""
echo "Funnel ${EVENTS} → HTTP ${FUNNEL_CODE}"
if [[ "${FUNNEL_CODE}" == "401" || "${FUNNEL_CODE}" == "403" ]]; then
  echo "OK — endpoint valmis (401/403)."
else
  echo "VIRHE: odotettiin 401/403, sain ${FUNNEL_CODE}."
  exit 1
fi
