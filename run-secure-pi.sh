#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${PI_SECURE_IMAGE:-secure-pi:latest}"
REBUILD="${PI_REBUILD:-0}"
PI_AUTH_FILE="${PI_AUTH_FILE:-${HOME}/.pi/agent/auth.json}"

resolve_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
  else
    echo "$1"
  fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  ./run-secure-pi.sh [repo-path] [pi-args...]

Examples:
  ./run-secure-pi.sh .
  ./run-secure-pi.sh /<path-to-repo> -p "summarize this codebase"

Env toggles:
  PI_REBUILD=1              Rebuild image before run
  PI_VERSION=0.80.2         Override default pi version at build time
  PI_DOCKER_NETWORK_NONE=1  Disable outbound network completely
  PI_WORKSPACE_READONLY=1   Mount workspace read-only
  PI_DISABLE_EXTENSIONS=1   Disable packages/extensions loaded from settings.json
  PI_DISABLE_BASH_TOOL=1    Disable bash tool in pi
  PI_ALLOW_CONTEXT_FILES=0  Disable AGENTS.md / CLAUDE.md loading
EOF
  exit 0
fi

PI_VERSION="${PI_VERSION:-0.80.2}"

if [[ $# -eq 0 || "${1}" == -* ]]; then
  REPO_PATH="$(pwd)"
else
  REPO_PATH="$1"
  shift
fi

if [[ ! -d "${REPO_PATH}" ]]; then
  echo "Repository path does not exist: ${REPO_PATH}" >&2
  exit 1
fi

REPO_PATH="$(resolve_path "${REPO_PATH}")"

HOST_PI_AUTH_FILE="${PI_AUTH_FILE:-${HOME}/.pi/agent/auth.json}"

AUTH_DIR="$(dirname "${HOST_PI_AUTH_FILE}")"
mkdir -p "${AUTH_DIR}"
if [[ ! -f "${HOST_PI_AUTH_FILE}" ]]; then
  printf '{}\n' >"${HOST_PI_AUTH_FILE}"
fi
HOST_PI_AUTH_FILE="$(resolve_path "${HOST_PI_AUTH_FILE}")"
PI_AUTH_JSON_BASE64="$(base64 <"${HOST_PI_AUTH_FILE}" | tr -d '\n')"

if [[ "${REBUILD}" == "1" ]] || ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "[secure-pi] Building image ${IMAGE} (PI_VERSION=${PI_VERSION})"
  docker build --build-arg "PI_VERSION=${PI_VERSION}" -t "${IMAGE}" "${SCRIPT_DIR}"
fi

DOCKER_NETWORK_ARGS=()
if [[ "${PI_DOCKER_NETWORK_NONE:-0}" == "1" ]]; then
  DOCKER_NETWORK_ARGS=(--network none)
fi

WORKSPACE_MOUNT="type=bind,src=${REPO_PATH},dst=/workspace"
if [[ "${PI_WORKSPACE_READONLY:-0}" == "1" ]]; then
  WORKSPACE_MOUNT="type=bind,src=${REPO_PATH},dst=/workspace,readonly"
fi

docker run --rm -it \
  --workdir /workspace \
  --user 10001:10001 \
  --mount "${WORKSPACE_MOUNT}" \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=256m \
  --tmpfs /run:rw,noexec,nosuid,uid=10001,gid=10001,mode=0700,size=4m \
  --mount type=volume,src=secure-pi-agent,dst=/home/pi/.pi \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --pids-limit "${PI_PIDS_LIMIT:-512}" \
  --memory "${PI_MEMORY_LIMIT:-4g}" \
  --cpus "${PI_CPU_LIMIT:-2}" \
  -e PI_OFFLINE=1 \
  -e PI_SKIP_VERSION_CHECK=1 \
  -e PI_TELEMETRY=0 \
  -e PI_ALLOW_CONTEXT_FILES="${PI_ALLOW_CONTEXT_FILES:-1}" \
  -e PI_DISABLE_BASH_TOOL="${PI_DISABLE_BASH_TOOL:-0}" \
  -e PI_AUTH_JSON_BASE64="${PI_AUTH_JSON_BASE64}" \
  "${DOCKER_NETWORK_ARGS[@]}" \
  "${IMAGE}" \
  "$@"
