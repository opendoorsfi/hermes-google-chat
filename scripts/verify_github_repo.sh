#!/usr/bin/env bash
# Tarkista ennen pushia: repo löytyy ja token toimii.
#
#   export GH_TOKEN=ghp_oikea_token   # EI placeholder ghp_xxxx
#   bash scripts/verify_github_repo.sh

set -euo pipefail

REPO="${HERMES_GITHUB_REPO:-opendoorsfi/hermes-google-chat}"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "VIRHE: GH_TOKEN puuttuu"
  echo "  export GH_TOKEN=ghp_...   # fine-grained PAT, Contents Read/Write"
  exit 1
fi

if [[ "${GH_TOKEN}" == "ghp_xxxx" ]] || [[ "${GH_TOKEN}" == *"xxxx"* ]]; then
  echo "VIRHE: GH_TOKEN on placeholder (ghp_xxxx) — luo oikea PAT GitHubissa"
  echo "  https://github.com/settings/tokens?type=beta"
  echo "  Repository access: Only select → ${REPO} → Contents Read/Write"
  exit 1
fi

if [[ "${GH_TOKEN}" == ghp_github_pat_* ]]; then
  echo "VIRHE: GH_TOKEN alkaa ghp_github_pat_ — älä lisää ghp_-etuliitettä"
  echo "  Fine-grained token alkaa suoraan: github_pat_11..."
  echo "  Classic token alkaa: ghp_11..."
  echo "  Kopioi token sellaisenaan GitHubin näytöstä."
  exit 1
fi

if [[ "${GH_TOKEN}" != github_pat_* ]] && [[ "${GH_TOKEN}" != ghp_* ]]; then
  echo "VAROITUS: token ei näytä GitHub PAT:lta (odotetaan github_pat_... tai ghp_...)"
fi

echo "==> Tarkistetaan ${REPO} (API)"
HTTP=$(curl -sS -o /tmp/hermes-repo-check.json -w '%{http_code}' \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}")

case "${HTTP}" in
  200)
    NAME=$(python3 -c "import json; print(json.load(open('/tmp/hermes-repo-check.json'))['full_name'])" 2>/dev/null || echo "${REPO}")
    echo "OK: repo löytyi — ${NAME}"
    echo "==> Push:"
    echo "  cd /tmp/hermes-google-chat-export"
    echo "  git remote remove origin 2>/dev/null || true"
    echo "  git remote add origin \"https://x-access-token:\${GH_TOKEN}@github.com/${REPO}.git\""
    echo "  git push -u origin main"
    ;;
  404)
    echo "VIRHE: 404 — repo ${REPO} ei ole olemassa TAI tokenilla ei ole oikeutta"
    echo ""
    echo "Tarkista selaimessa (kirjautuneena org-tilille):"
    echo "  https://github.com/${REPO}"
    echo ""
    echo "Jos 404 selaimessakin → luo repo ensin:"
    echo "  https://github.com/organizations/opendoorsfi/repositories/new"
    echo "  Nimi: hermes-google-chat, Private, EI README/gitignore"
    echo ""
    echo "Jos repo näkyy selaimessa → PAT väärä tai ei repo-oikeutta"
    exit 1
    ;;
  401)
    echo "VIRHE: 401 — GH_TOKEN on virheellinen tai vanhentunut"
    exit 1
    ;;
  *)
    echo "VIRHE: GitHub API ${HTTP}"
    cat /tmp/hermes-repo-check.json 2>/dev/null || true
    exit 1
    ;;
esac
