#!/usr/bin/env bash
# Käynnistä Hermes Google Chat host (gateway + Tailscale Funnel) — yksi komento.
#
#   curl -fsSL https://raw.githubusercontent.com/opendoorsfi/hermes-google-chat/main/scripts/start_hermes_now.sh | bash
#
# Linux (work-h): sudo bash scripts/start_hermes_now.sh
# macOS:          bash scripts/start_hermes_now.sh natalia@info.opendoors.fi
set -euo pipefail

EMAIL="${1:-ipad@info.opendoors.fi}"
REPO="${HERMES_REPO_DIR:-}"
if [[ -z "${REPO}" ]]; then
  for d in "${HOME}/hermes-google-chat" "${HOME}/projects/hermes-google-chat" "/opt/hermes-google-chat"; do
    if [[ -d "${d}/scripts/bootstrap_hermes_host.sh" ]]; then
      REPO="${d}"
      break
    fi
  done
fi
if [[ -z "${REPO}" ]]; then
  REPO="$(mktemp -d)"
  echo "==> Clone repo → ${REPO}"
  git clone --depth 1 https://github.com/opendoorsfi/hermes-google-chat.git "${REPO}"
  CLONED=1
else
  CLONED=0
fi

cd "${REPO}"
git pull --ff-only 2>/dev/null || true
python3 scripts/chat_registry.py generate-all >/dev/null 2>&1 || true

if [[ "$(uname -s)" == "Darwin" ]]; then
  bash scripts/bootstrap_hermes_mac.sh "${EMAIL}"
else
  if [[ "${EUID}" -ne 0 ]]; then
    echo "==> Linux: tarvitaan sudo (systemd + funnel)"
    exec sudo bash "$0" "${EMAIL}"
  fi
  bash scripts/bootstrap_hermes_host.sh
fi

echo ""
echo "==> Testaa Google Chatissa: Find apps → hermes-chat → Hei"
if [[ "${CLONED}" == "1" ]]; then
  echo "    Repo: ${REPO} (voit siirtää pysyvään paikkaan)"
fi
