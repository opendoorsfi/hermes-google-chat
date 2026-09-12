#!/usr/bin/env bash
# Diagnostiikka + automaattinen korjaus AzuraCast-syncille (Cloud Run + radio.opendoors.fi).
#
#   bash scripts/self_heal_azuracast.sh          # vain diagnoosi
#   bash scripts/self_heal_azuracast.sh --apply  # korjaa mitä pystyy (CI)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

REG="${ROOT}/config/registry.json"
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "${REG}" >/dev/null

read_cfg() {
  python3 -c "import json; print(json.load(open('${REG}'))$1)"
}

GCP_PROJECT="$(read_cfg "['gcp_project']")"
REGION="$(read_cfg "['gcp_region']")"
SERVICE="$(read_cfg "['cloud_run_service']")"
CR_URL="$(read_cfg "['cloud_run_url']")"
CR_PILOT="$(read_cfg "['cloud_run_pilot_url']")"
AZ_URL="$(read_cfg "['azuracast_base_url']")"

ISSUES=()
FIXED=()

note_issue() { ISSUES+=("$1"); echo "ISSUE: $1"; }
note_fixed() { FIXED+=("$1"); echo "FIXED: $1"; }

section() { echo ""; echo "=== $* ==="; }

http_ok() {
  local url="$1"
  local code
  code="$(curl -fsS -o /dev/null -w "%{http_code}" --connect-timeout 15 --max-time 30 "${url}" 2>/dev/null || echo "000")"
  [[ "${code}" == "200" ]]
}

section "Diagnoosi — ${GCP_PROJECT}"

# --- AzuraCast API ---
if http_ok "${AZ_URL}/api/status"; then
  echo "OK: AzuraCast ${AZ_URL}/api/status"
else
  note_issue "AzuraCast ei vastaa (${AZ_URL}/api/status)"
fi

# --- Cloud Run prod ---
CR_OK=0
if http_ok "${CR_URL}/health"; then
  echo "OK: Cloud Run ${SERVICE} /health (${CR_URL})"
  CR_OK=1
else
  note_issue "Cloud Run ${SERVICE} /health ei 200 (${CR_URL})"
fi

# --- Cloud Run pilot (valinnainen) ---
if [[ -n "${CR_PILOT}" ]]; then
  if http_ok "${CR_PILOT}/health"; then
    echo "OK: pilot /health (${CR_PILOT})"
  else
    note_issue "Pilot Cloud Run /health ei 200 (${CR_PILOT})"
  fi
fi

# --- Process endpoint reachable ---
ROOT_BODY="$(curl -fsS --connect-timeout 15 --max-time 30 "${CR_URL}/" 2>/dev/null || true)"
if echo "${ROOT_BODY}" | grep -q 'POST /process'; then
  echo "OK: Cloud Run root endpoint (POST /process)"
else
  note_issue "Cloud Run root ei palauta odotettua vastausta"
fi

# --- AzuraCast API key (valinnainen) ---
if [[ -n "${AZURACAST_API_KEY:-}" ]]; then
  CODE="$(curl -fsS -o /dev/null -w "%{http_code}" --connect-timeout 15 --max-time 30 \
    -H "Authorization: Bearer ${AZURACAST_API_KEY}" \
    "${AZ_URL}/api/admin/server/stats" 2>/dev/null || echo "000")"
  if [[ "${CODE}" == "200" ]]; then
    echo "OK: AzuraCast API key (admin/stats)"
  else
    note_issue "AzuraCast API key epäonnistui (HTTP ${CODE})"
  fi
else
  echo "SKIP: AZURACAST_API_KEY puuttuu — API-auth ei testattu"
fi

# --- GCP Cloud Run describe (jos gcloud + creds; HTTP on ensisijainen) ---
GCLOUD_WARN=""
if command -v gcloud >/dev/null 2>&1; then
  if gcloud run services describe "${SERVICE}" \
    --project="${GCP_PROJECT}" --region="${REGION}" &>/dev/null; then
    READY="$(gcloud run services describe "${SERVICE}" \
      --project="${GCP_PROJECT}" --region="${REGION}" \
      --format='value(status.conditions.status)' 2>/dev/null || true)"
    if echo "${READY}" | grep -q True; then
      echo "OK: gcloud Cloud Run Ready"
    else
      GCLOUD_WARN="gcloud: Cloud Run ${SERVICE} ei Ready"
      echo "WARN: ${GCLOUD_WARN}"
    fi
  else
    GCLOUD_WARN="gcloud: ei pääsyä tai ${SERVICE} ei näy (HTTP voi silti olla OK)"
    echo "WARN: ${GCLOUD_WARN}"
  fi
else
  echo "SKIP: gcloud puuttuu — GCP-tarkistus vain HTTP:llä"
fi

# --- Korjaukset ---
if [[ "${APPLY}" == "1" ]]; then
  section "Korjaukset (--apply)"

  if [[ "${CR_OK}" == "0" ]] && command -v gcloud >/dev/null 2>&1; then
    if gcloud run services describe "${SERVICE}" \
      --project="${GCP_PROJECT}" --region="${REGION}" &>/dev/null; then
      echo ">> Cloud Run traffic reset (pakota uusi instanssi)"
      IMAGE="$(gcloud run services describe "${SERVICE}" \
        --project="${GCP_PROJECT}" --region="${REGION}" \
        --format='value(spec.template.spec.containers[0].image)' 2>/dev/null || true)"
      if [[ -n "${IMAGE}" ]]; then
        gcloud run deploy "${SERVICE}" \
          --project="${GCP_PROJECT}" --region="${REGION}" \
          --image="${IMAGE}" --quiet 2>/dev/null && note_fixed "Cloud Run redeploy (sama image)" || \
          note_issue "Cloud Run redeploy epäonnistui"
      fi
    elif [[ -x "${ROOT}/scripts/deploy_cloudrun.sh" ]]; then
      echo ">> deploy_cloudrun.sh"
      if bash "${ROOT}/scripts/deploy_cloudrun.sh"; then
        note_fixed "Cloud Run deploy"
        CR_OK=1
      else
        note_issue "deploy_cloudrun.sh epäonnistui"
      fi
    fi
  fi

  # Uudelleentarkista HTTP
  if http_ok "${CR_URL}/health"; then
    note_fixed "Cloud Run /health OK korjauksen jälkeen"
    CR_OK=1
  fi
fi

section "Yhteenveto"
echo "AzuraCast:  ${AZ_URL}"
echo "Cloud Run:  ${CR_URL}"
echo "Ongelmia:   ${#ISSUES[@]}"
echo "Korjauksia: ${#FIXED[@]}"
if [[ "${#ISSUES[@]}" -gt 0 ]]; then
  printf '  - %s\n' "${ISSUES[@]}"
fi

if [[ "${#ISSUES[@]}" -eq 0 ]]; then
  echo ""
  echo "OK — yhteys näyttää kunnossa"
  [[ -n "${GCLOUD_WARN}" ]] && echo "HUOM: ${GCLOUD_WARN}"
  exit 0
fi

# HTTP OK mutta vain gcloud-varoitus → ei estä
if [[ "${CR_OK}" == "1" && "${#ISSUES[@]}" -eq 0 ]]; then
  exit 0
fi

exit 1
