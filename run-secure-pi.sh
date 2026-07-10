#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${PI_SECURE_IMAGE:-secure-pi:latest}"
REBUILD="${PI_REBUILD:-0}"
# Auth lives entirely in the Docker volume. Container is self-sufficient.
# To pre-seed auth (e.g. CI/CD), set PI_AUTH_JSON_BASE64 externally.

resolve_path() {
	if command -v realpath >/dev/null 2>&1; then
		realpath "$1"
	elif command -v python3 >/dev/null 2>&1; then
		python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
	else
		echo "$1"
	fi
}

detect_target_arch() {
	case "$(uname -m)" in
	x86_64) echo "amd64" ;;
	aarch64 | arm64) echo "arm64" ;;
	*) echo "" ;;
	esac
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	cat <<'EOF'
EOF
	exit 0
fi

PI_VERSION="${PI_VERSION:-}"

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

if [[ "${REBUILD}" == "1" ]] || ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
	BUILD_ARGS=()
	TARGETARCH="${PI_TARGETARCH:-$(detect_target_arch)}"
	BUILD_PLATFORM="${PI_BUILD_PLATFORM:-}"

	if [[ -n "${PI_VERSION}" ]]; then
		BUILD_ARGS+=(--build-arg "PI_VERSION=${PI_VERSION}")
	fi

	if [[ -n "${TARGETARCH}" ]]; then
		BUILD_ARGS+=(--build-arg "TARGETARCH=${TARGETARCH}")
	fi

	if [[ -n "${PI_NODE_BASE_IMAGE_ARM64:-}" ]]; then
		BUILD_ARGS+=(--build-arg "NODE_BASE_IMAGE_ARM64=${PI_NODE_BASE_IMAGE_ARM64}")
	fi

	if [[ -n "${BUILD_PLATFORM}" ]]; then
		BUILD_ARGS+=(--platform "${BUILD_PLATFORM}")
	fi

	if [[ -n "${PI_VERSION}" ]]; then
		echo "[secure-pi] Building image ${IMAGE} (PI_VERSION=${PI_VERSION}, TARGETARCH=${TARGETARCH:-default}${BUILD_PLATFORM:+, PLATFORM=${BUILD_PLATFORM}})"
	else
		echo "[secure-pi] Building image ${IMAGE} (PI_VERSION from Dockerfile ARG, TARGETARCH=${TARGETARCH:-default}${BUILD_PLATFORM:+, PLATFORM=${BUILD_PLATFORM}})"
	fi

	docker build "${BUILD_ARGS[@]}" -t "${IMAGE}" "${SCRIPT_DIR}"
fi

# Fix volume dir permissions for existing volumes initialized with wrong ownership.
# Runs as root (no --user, no --cap-drop) before the hardened main container.
# No-op if already correct. The Dockerfile sets 1777 for new volumes.
docker run --rm \
	--mount type=volume,src=secure-pi-agent,dst=/pi-agent \
	--entrypoint sh \
	"${IMAGE}" \
	-c 'chmod 1777 /pi-agent 2>/dev/null || true'

DOCKER_NETWORK_ARGS=()
if [[ "${PI_DOCKER_NETWORK_NONE:-0}" == "1" ]]; then
	DOCKER_NETWORK_ARGS=(--network none)
fi

WORKSPACE_MOUNT="type=bind,src=${REPO_PATH},dst=/workspace"
if [[ "${PI_WORKSPACE_READONLY:-0}" == "1" ]]; then
	WORKSPACE_MOUNT="type=bind,src=${REPO_PATH},dst=/workspace,readonly"
fi

DEFAULT_CONTAINER_USER="$(id -u):$(id -g)"
CONTAINER_USER="${PI_CONTAINER_USER:-${DEFAULT_CONTAINER_USER}}"

docker run --rm -it \
	--workdir /workspace \
	--user "${CONTAINER_USER}" \
	--mount "${WORKSPACE_MOUNT}" \
	--read-only \
	--tmpfs /tmp:rw,noexec,nosuid,size=256m \
	--tmpfs /run:rw,noexec,nosuid,uid=0,gid=0,mode=0700,size=4m \
	--mount type=volume,src=secure-pi-agent,dst=/pi-agent \
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
	-e PI_DISABLE_EXTENSIONS="${PI_DISABLE_EXTENSIONS:-0}" \
	${PI_AUTH_JSON_BASE64:+-e "PI_AUTH_JSON_BASE64=${PI_AUTH_JSON_BASE64}"} \
	"${DOCKER_NETWORK_ARGS[@]}" \
	"${IMAGE}" \
	"$@"
