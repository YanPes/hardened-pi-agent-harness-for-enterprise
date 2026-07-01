#!/usr/bin/env bash
set -euo pipefail

PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
PI_AUTH_FILE="${PI_AUTH_FILE:-/run/pi-auth.json}"
PI_AUTH_TARGET="${PI_AGENT_DIR}/auth.json"
mkdir -p "${PI_AGENT_DIR}"

if [[ -f "${PI_AUTH_FILE}" ]]; then
  cp -f "${PI_AUTH_FILE}" "${PI_AUTH_TARGET}"
fi

if [[ ! -f "${PI_AGENT_DIR}/settings.json" ]]; then
  cp /opt/pi-secure/settings.json "${PI_AGENT_DIR}/settings.json"
fi

sync_auth_file() {
  if [[ -f "${PI_AUTH_TARGET}" ]]; then
    cp -f "${PI_AUTH_TARGET}" "${PI_AUTH_FILE}"
    chmod 600 "${PI_AUTH_FILE}" 2>/dev/null || true
  fi
}

trap sync_auth_file EXIT

export PI_OFFLINE="${PI_OFFLINE:-1}"
export PI_SKIP_VERSION_CHECK="${PI_SKIP_VERSION_CHECK:-1}"
export PI_TELEMETRY="${PI_TELEMETRY:-0}"

SECURE_FLAGS=(
  --no-extensions
  --no-themes
)

if [[ "${PI_ALLOW_CONTEXT_FILES:-1}" == "0" ]]; then
  SECURE_FLAGS+=(--no-context-files)
fi

if [[ "${PI_DISABLE_BASH_TOOL:-0}" == "1" ]]; then
  SECURE_FLAGS+=(--tools read,edit,write,grep,find,ls)
fi

pi "${SECURE_FLAGS[@]}" "$@"
status=$?
exit "${status}"
