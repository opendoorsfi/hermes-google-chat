#!/usr/bin/env bash
# Launchd wrapper: lataa Pub/Sub + impersonation .env ennen hermes gateway run.
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
HERMES_BIN="${HERMES_BIN:-$(command -v hermes)}"
ENV_FILE="${HERMES_HOME}/.env"

export HERMES_HOME

if [[ -f "${ENV_FILE}" ]]; then
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    export "${key}=${val}"
  done < "${ENV_FILE}"
fi

if [[ -n "${GOOGLE_CHAT_IMPERSONATE_SERVICE_ACCOUNT:-}" ]]; then
  export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="${GOOGLE_CHAT_IMPERSONATE_SERVICE_ACCOUNT}"
fi

exec "${HERMES_BIN}" gateway run
