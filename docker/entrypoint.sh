#!/usr/bin/env bash
set -euo pipefail

PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
PI_AUTH_TARGET="${PI_AGENT_DIR}/auth.json"
PI_AUTH_JSON_BASE64="${PI_AUTH_JSON_BASE64:-}"

mkdir -p "${PI_AGENT_DIR}"

if [[ ! -s "${PI_AUTH_TARGET}" && -n "${PI_AUTH_JSON_BASE64}" ]]; then
  printf '%s' "${PI_AUTH_JSON_BASE64}" | base64 -d > "${PI_AUTH_TARGET}"
  chown pi:pi "${PI_AUTH_TARGET}"
fi

if [[ ! -f "${PI_AGENT_DIR}/settings.json" ]]; then
  cp /opt/pi-secure/settings.json "${PI_AGENT_DIR}/settings.json"
fi

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

if pi "${SECURE_FLAGS[@]}" "$@"; then
  status=0
else
  status=$?
fi

exit "${status}"
