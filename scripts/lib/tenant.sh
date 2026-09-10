#!/usr/bin/env bash
# Shared tenant manifest helpers (source, do not execute).
set -euo pipefail

tenant_root() {
  echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
}

tenant_config_path() {
  local tenant="$1"
  local root
  root="$(tenant_root)"
  if [[ -f "${root}/config/tenants/${tenant}.env" ]]; then
    echo "${root}/config/tenants/${tenant}.env"
  elif [[ -f "${root}/config/tenants/${tenant}.env.example" ]]; then
    echo "${root}/config/tenants/${tenant}.env.example"
  else
    echo "VIRHE: tenant config puuttuu: config/tenants/${tenant}.env" >&2
    return 1
  fi
}

load_tenant() {
  local tenant="$1"
  local cfg
  cfg="$(tenant_config_path "${tenant}")"
  # shellcheck disable=SC1090
  source "${cfg}"
  export TENANT GCP_PROJECT LINUX_USER PORT PATH_PREFIX ROLE
  export CHAT_APP_DISPLAY_NAME GOOGLE_CHAT_ALLOWED_USERS FUNNEL_BASE_URL
}

tenant_chat_http_url() {
  local base="${FUNNEL_BASE_URL%/}"
  local prefix="${PATH_PREFIX:-}"
  prefix="${prefix#/}"
  if [[ -n "${prefix}" ]]; then
    echo "${base}/${prefix}/api/platforms/google_chat/events"
  else
    echo "${base}/api/platforms/google_chat/events"
  fi
}

list_tenants() {
  local root dir f
  root="$(tenant_root)"
  for f in "${root}"/config/tenants/*.env "${root}"/config/tenants/*.env.example; do
    [[ -f "${f}" ]] || continue
    dir="$(basename "${f}")"
    dir="${dir%.env.example}"
    dir="${dir%.env}"
    echo "${dir}"
  done | sort -u
}
