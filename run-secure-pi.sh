#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${PI_SECURE_IMAGE:-secure-pi:latest}"
PI_VERSION="${PI_VERSION:-latest}"
REBUILD="${PI_REBUILD:-0}"
PI_AUTH_FILE="${PI_AUTH_FILE:-${HOME}/.secure-pi/auth.json}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  ./run-secure-pi.sh [repo-path] [pi-args...]

Examples:
  ./run-secure-pi.sh .
  ./run-secure-pi.sh /<path-to-repo> -p "summarize this codebase"

Env toggles:
  PI_REBUILD=1              Rebuild image before run
  PI_VERSION=0.42.0         Pin pi version at build time
  PI_DOCKER_NETWORK_NONE=1  Disable network completely
  PI_DISABLE_BASH_TOOL=1    Disable bash tool in pi
  PI_ALLOW_CONTEXT_FILES=0  Disable AGENTS.md / CLAUDE.md loading
EOF
  exit 0
fi

if [[ $# -eq 0 ]]; then
  REPO_PATH="$(pwd)"
else
  REPO_PATH="$1"
  shift
fi

if [[ ! -d "${REPO_PATH}" ]]; then
  echo "Repository path does not exist: ${REPO_PATH}" >&2
  exit 1
fi

REPO_PATH="$(realpath "${REPO_PATH}")"

AUTH_DIR="$(dirname "${PI_AUTH_FILE}")"
mkdir -p "${AUTH_DIR}"
if [[ ! -f "${PI_AUTH_FILE}" ]]; then
  printf '{}\n' >"${PI_AUTH_FILE}"
fi
chmod a+rw "${PI_AUTH_FILE}" 2>/dev/null || true
PI_AUTH_FILE="$(realpath "${PI_AUTH_FILE}")"

if [[ "${REBUILD}" == "1" ]] || ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "[secure-pi] Building image ${IMAGE} (PI_VERSION=${PI_VERSION})"
  docker build --build-arg "PI_VERSION=${PI_VERSION}" -t "${IMAGE}" "${SCRIPT_DIR}"
fi

DOCKER_NETWORK_ARGS=()
if [[ "${PI_DOCKER_NETWORK_NONE:-0}" == "1" ]]; then
  DOCKER_NETWORK_ARGS+=(--network none)
fi

docker run --rm -it \
  --workdir /workspace \
  --user 10001:10001 \
  --mount "type=bind,src=${REPO_PATH},dst=/workspace" \
  --mount "type=bind,src=${PI_AUTH_FILE},dst=/opt/pi-secure/auth.json" \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=256m \
  --tmpfs /home/pi/.pi:rw,nosuid,uid=10001,gid=10001,mode=0700,size=256m \
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
  "${DOCKER_NETWORK_ARGS[@]}" \
  "${IMAGE}" \
  "$@"
