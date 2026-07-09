#!/usr/bin/env bash
set -euo pipefail

PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
PI_AUTH_JSON_BASE64="${PI_AUTH_JSON_BASE64:-}"

# Volume dir is 1777 (set at image build). mkdir -p should always succeed.
# If it fails the container cannot function; we abort with a clear message.
if ! mkdir -p "${PI_AGENT_DIR}" 2>/dev/null; then
  echo "[secure-pi] FATAL: ${PI_AGENT_DIR} not writable by uid=$(id -u). Recreate the 'secure-pi-agent' volume and retry." >&2
  exit 1
fi

PI_AUTH_TARGET="${PI_AGENT_DIR}/auth.json"

# PI_AUTH_JSON_BASE64 is optional — only used for CI/CD pre-seeding.
# Normal flow: user runs /login once; token persists in the volume.
if [[ ! -s "${PI_AUTH_TARGET}" && -n "${PI_AUTH_JSON_BASE64}" ]]; then
  if ! printf '%s' "${PI_AUTH_JSON_BASE64}" | base64 -d >"${PI_AUTH_TARGET}" 2>/dev/null; then
    echo "[secure-pi] WARN: could not write ${PI_AUTH_TARGET}; skipping auth pre-seed." >&2
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
