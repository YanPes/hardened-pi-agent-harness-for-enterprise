#!/usr/bin/env bash
set -euo pipefail

PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
PI_AUTH_JSON_BASE64="${PI_AUTH_JSON_BASE64:-}"

ensure_writable_agent_dir() {
  local dir="$1"
  mkdir -p "${dir}" 2>/dev/null || return 1
  local probe="${dir}/.pi-write-probe"
  if : >"${probe}" 2>/dev/null; then
    rm -f "${probe}" || true
    return 0
  fi
  return 1
}

if ! ensure_writable_agent_dir "${PI_AGENT_DIR}"; then
  FALLBACK_AGENT_DIR="/tmp/pi-agent"
  echo "[secure-pi] WARN: ${PI_AGENT_DIR} not writable by uid=$(id -u). Falling back to ${FALLBACK_AGENT_DIR}." >&2
  ensure_writable_agent_dir "${FALLBACK_AGENT_DIR}"
  PI_AGENT_DIR="${FALLBACK_AGENT_DIR}"
  export PI_CODING_AGENT_DIR="${PI_AGENT_DIR}"
fi

PI_AUTH_TARGET="${PI_AGENT_DIR}/auth.json"

if [[ ! -s "${PI_AUTH_TARGET}" && -n "${PI_AUTH_JSON_BASE64}" ]]; then
  if ! printf '%s' "${PI_AUTH_JSON_BASE64}" | base64 -d >"${PI_AUTH_TARGET}" 2>/dev/null; then
    echo "[secure-pi] WARN: cannot write ${PI_AUTH_TARGET}; skipping auth import." >&2
  fi
fi

if [[ ! -f "${PI_AGENT_DIR}/settings.json" ]]; then
  cp /opt/pi-secure/settings.json "${PI_AGENT_DIR}/settings.json"
fi

# Sync pre-installed packages from the image seed into the agent volume.
# Uses cp -rn (no-clobber) so existing user-installed packages are preserved,
# but any package present in the image seed and missing from the volume is added.
# This runs on every start so rebuilt images propagate new/updated skills.
PI_SEED_DIR="/opt/pi-agent-seed"
if [[ -d "${PI_SEED_DIR}/git" ]]; then
  mkdir -p "${PI_AGENT_DIR}/git"
  echo "[secure-pi] Syncing seed packages into agent volume..."
  cp -rn "${PI_SEED_DIR}/git/." "${PI_AGENT_DIR}/git/"
fi

export PI_OFFLINE="${PI_OFFLINE:-1}"
export PI_SKIP_VERSION_CHECK="${PI_SKIP_VERSION_CHECK:-1}"
export PI_TELEMETRY="${PI_TELEMETRY:-0}"

SECURE_FLAGS=(
  --no-themes
)

if [[ "${PI_DISABLE_EXTENSIONS:-0}" == "1" ]]; then
  SECURE_FLAGS+=(--no-extensions)
fi

if [[ "${PI_ALLOW_CONTEXT_FILES:-1}" == "0" ]]; then
  SECURE_FLAGS+=(--no-context-files)
fi

if [[ "${PI_DISABLE_BASH_TOOL:-0}" == "1" ]]; then
  SECURE_FLAGS+=(--tools read edit write grep find ls)
fi

if pi "${SECURE_FLAGS[@]}" "$@"; then
  status=0
else
  status=$?
fi

exit "${status}"
