#!/usr/bin/env bash
# Push standalone export to opendoorsfi/hermes-google-chat.
#
# Vaatii tokenin jolla on repo-oikeus (org private repo):
#   export GH_TOKEN=ghp_xxxx   # fine-grained: Contents Read/Write on hermes-google-chat
#   bash scripts/push_to_github.sh
#
# Tai asenna gh ipad-tilillä: gh auth login

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${EXPORT_DIR:-/tmp/hermes-google-chat-export}"
REMOTE="${HERMES_REPO:-git@github.com:opendoorsfi/hermes-google-chat.git}"
BRANCH="${BRANCH:-main}"

if [[ ! -d "${DEST}/.git" ]]; then
  echo "==> Export puuttuu — luodaan ${DEST}"
  if [[ -f "${ROOT}/../scripts/export_hermes_google_chat_repo.sh" ]]; then
    bash "${ROOT}/../scripts/export_hermes_google_chat_repo.sh" "${DEST}"
  elif [[ -f "${ROOT}/scripts/export_repo.sh" ]]; then
    bash "${ROOT}/scripts/export_repo.sh" "${DEST}"
  else
    echo "VIRHE: aja export ensin"
    exit 1
  fi
fi

cd "${DEST}"

if [[ -n "${GH_TOKEN:-}" ]]; then
  REMOTE="https://x-access-token:${GH_TOKEN}@github.com/opendoorsfi/hermes-google-chat.git"
fi

echo "==> Tarkista repo-oikeus"
if command -v gh >/dev/null 2>&1; then
  if ! gh repo view opendoorsfi/hermes-google-chat --json name >/dev/null 2>&1; then
    echo "VIRHE: gh ei näe repoa opendoorsfi/hermes-google-chat"
    echo "  - Varmista URL selaimessa (org vs henkilökohtainen tili)"
    echo "  - gh auth login oikealla tilillä (org-admin / repo write)"
    echo "  - tai export GH_TOKEN=ghp_... (Contents write)"
    exit 1
  fi
  echo "OK: repo löytyi"
fi

git remote remove origin 2>/dev/null || true
git remote add origin "${REMOTE}"

echo "==> Push ${BRANCH} → opendoorsfi/hermes-google-chat"
if git push -u origin "${BRANCH}"; then
  echo "OK — https://github.com/opendoorsfi/hermes-google-chat"
  exit 0
fi

echo "==> Push hylätty — yritetään rebase jos remote README"
git fetch origin "${BRANCH}" 2>/dev/null || true
if git rev-parse "origin/${BRANCH}" >/dev/null 2>&1; then
  git pull origin "${BRANCH}" --rebase --allow-unrelated-histories || true
  git push -u origin "${BRANCH}"
else
  exit 1
fi
