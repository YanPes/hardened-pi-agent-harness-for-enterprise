#!/usr/bin/env bash
set -euo pipefail

PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
PI_AUTH_PATH="${PI_AUTH_PATH:-/opt/pi-secure/auth.json}"
mkdir -p "${PI_AGENT_DIR}"

ln -sfn "${PI_AUTH_PATH}" "${PI_AGENT_DIR}/auth.json"

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

exec pi "${SECURE_FLAGS[@]}" "$@"
