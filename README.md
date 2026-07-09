# zero-trust-pi-agent-harness

Hardened Docker wrapper for `pi` (https://pi.dev/) suitable for zero-trust enterprise environments. `secure-pi` launches `pi` in a locked-down container with secure defaults, minimizing attack surface while maintaining core functionality for codebase and LLM interactions.

## What this setup enforces

- **Repo scoping**: only one host repository is mounted to `/workspace`
- **Read-only container root filesystem**: blocks writes outside mounted tmpfs + repo
- **Runtime user configurable**: defaults to host-matching uid:gid in `run-secure-pi.sh` (for workspace write access); override with `PI_CONTAINER_USER=<uid:gid>` when needed
- **Dropped Linux capabilities**: `--cap-drop ALL`
- **No privilege escalation**: `no-new-privileges:true`
- **Constrained resources**: CPU, memory, PID limits
- **Telemetry and update checks disabled**:
  - `enableInstallTelemetry: false` (settings)
  - `PI_TELEMETRY=0`
  - `PI_SKIP_VERSION_CHECK=1`
  - `PI_OFFLINE=1` (disables startup network checks)
- **Untrusted dynamic resources mostly enabled for UX**:
  - extensions allowed by default so `packages` in `settings.json` can load
  - themes still disabled by default

> **Intentional UX/Security tradeoffs:**
>
> - `~/.pi` state (including auth) is persisted in dedicated Docker volume (`secure-pi-agent`) — the container is fully self-sufficient. One-time `/login` inside the container writes the token to the volume; it persists across restarts with no host file involvement. For CI/CD pre-seeding, set `PI_AUTH_JSON_BASE64` externally.
> - Extensions are allowed by default so curated packages from `settings.json` work out of the box; disable them only when you need a stricter profile.
> - `Skills` and `prompt templates` are intentionally enabled for developer experience.

## Files

- `Dockerfile` - hardened `pi` image
- `bin/setup.js` - shell alias helper for `npx` / `pnpx`
- `docker/entrypoint.sh` - secure defaults + startup config bootstrap
- `config/settings.json` - telemetry-off base settings
- `run-secure-pi.sh` - all-in-one Linux/macOS wrapper (auto-build + run)
- `docker-compose.yml` - compose alternative

## Getting started

### Recommended: `npx` / `pnpx`

If this repo is published as a package, run the setup binary:

```bash
npx zero-trust-pi-agent-harness
# or
pnpx zero-trust-pi-agent-harness
```

This adds a `pi` alias to `~/.bashrc` or `~/.zshrc` that points to `run-secure-pi.sh`.

Restart your shell, then run:

```bash
pi /absolute/path/to/repo
pi -p "summarize this codebase"
```

### Local clone fallback

If you have the repo cloned locally, you can still run the wrapper directly:

```bash
chmod +x run-secure-pi.sh
./run-secure-pi.sh /absolute/path/to/repo
```

Ensure LF line endings in shell scripts:

```bash
perl -pi -e 's/\r$//' run-secure-pi.sh docker/entrypoint.sh bin/setup.js
```

## Build (optional)

The run scripts auto-build the image if it does not exist.

Manual build:

```bash
docker build -t secure-pi:latest .
```

Build for a specific architecture:

```bash
# Native ARM64 build
docker build --build-arg TARGETARCH=arm64 --platform linux/arm64 -t secure-pi:arm64 .

# Native x86_64/AMD64 build
docker build --build-arg TARGETARCH=amd64 --platform linux/amd64 -t secure-pi:amd64 .
```

Pin a specific Pi version:

```bash
docker build --build-arg PI_VERSION=0.42.0 -t secure-pi:0.42.0 .
```

Base image SHA pinning:

- AMD64 base image is pinned by default in `Dockerfile`.
- For ARM64 SHA pinning, pass a digest explicitly:

```bash
docker build \
  --build-arg TARGETARCH=arm64 \
  --build-arg NODE_BASE_IMAGE_ARM64=node:22-bookworm-slim@sha256:<arm64-or-manifest-digest> \
  --platform linux/arm64 \
  -t secure-pi:arm64 .
```

## Run (recommended all-in-one)

### Linux / macOS

From the repo you want Pi to access:

```bash
./run-secure-pi.sh .
```

Or pass a path explicitly:

```bash
./run-secure-pi.sh /absolute/path/to/repo
```

Pass normal Pi arguments after the repo path:

```bash
./run-secure-pi.sh /<path-to-repo> -p "summarize this codebase"
./run-secure-pi.sh /<path-to-repo> "find dead code"
```

Or run from inside the target repo and omit the path:

```bash
./run-secure-pi.sh -p "summarize this codebase"
```

## Security toggles

- Disable context-file loading (`AGENTS.md`/`CLAUDE.md`):

```bash
PI_ALLOW_CONTEXT_FILES=0 ./run-secure-pi.sh /<path-to-repo>/
```

- Disable `bash` tool from the LLM toolset:

```bash
PI_DISABLE_BASH_TOOL=1 ./run-secure-pi.sh /<path-to-repo>/
```

- Disable extensions/packages:

```bash
PI_DISABLE_EXTENSIONS=1 ./run-secure-pi.sh /<path-to-repo>/
```

- Disable outbound network (default allows network):

```bash
PI_DOCKER_NETWORK_NONE=1 ./run-secure-pi.sh /<path-to-repo>/
```

- Force workspace read-only (default is writable):

```bash
PI_WORKSPACE_READONLY=1 ./run-secure-pi.sh /<path-to-repo>/
```

- Override runtime user explicitly:

```bash
PI_CONTAINER_USER=10001:10001 ./run-secure-pi.sh /<path-to-repo>/
```

- Override built-in Pi version pin:

```bash
PI_VERSION=0.42.0 ./run-secure-pi.sh /<path-to-repo>/
```

- Force build architecture when auto-detect is not desired:

```bash
PI_TARGETARCH=arm64 ./run-secure-pi.sh /<path-to-repo>/
PI_TARGETARCH=amd64 ./run-secure-pi.sh /<path-to-repo>/
```

- Pass explicit Docker build platform (useful with buildx/emulation):

```bash
PI_BUILD_PLATFORM=linux/arm64 ./run-secure-pi.sh /<path-to-repo>/
```

- Override ARM64 base image (for digest pinning):

```bash
PI_NODE_BASE_IMAGE_ARM64='node:22-bookworm-slim@sha256:<digest>' ./run-secure-pi.sh /<path-to-repo>/
```

## Linux users / UIDs used by this setup

These identities are used for different stages (build, startup, runtime). They are not all privileged at the same time.

| UID:GID | Name / source | Where used | Why |
| --- | --- | --- | --- |
| `0:0` | `root` | Image build steps; optional runtime if you explicitly set `PI_CONTAINER_USER=0:0` | Needed for package install and system setup during image build. Runtime root is **not** the default. |
| `10001:10001` | `pi` (user created in `Dockerfile`) | Owner of `/opt/pi` and baked-in Pi install/seed data | Dedicated non-root service user inside the image. Good fixed UID option when you want deterministic container identity. |
| `1000:1000` | Typical first Linux desktop user | `docker-compose.yml` fallback default: `user: "${PI_CONTAINER_USER:-1000:1000}"` | Sensible compose default on many Linux hosts, but can be overridden. |
| `<host_uid>:<host_gid>` | Current host user | Default for `run-secure-pi.sh` (`id -u:id -g`) | Prevents permission mismatch when editing files in mounted `/workspace`. |

Quick override examples:

```bash
# Fixed non-root service identity
PI_CONTAINER_USER=10001:10001 ./run-secure-pi.sh /<path-to-repo>/

# Explicit root (only if you intentionally need it)
PI_CONTAINER_USER=0:0 ./run-secure-pi.sh /<path-to-repo>/
```

## Compose usage

Pi state (including auth) is persisted automatically in Docker volume `secure-pi-agent` (mounted at `/pi-agent`).

Run:

```bash
export REPO_PATH=/absolute/path/to/repo
docker compose run --rm pi
```

With prompt:

```bash
docker compose run --rm pi -p "review this repository"
```

## Notes for enterprise security review

1. This setup blocks Pi's own telemetry/update endpoints via config/env (`PI_OFFLINE`, `PI_SKIP_VERSION_CHECK`, `PI_TELEMETRY=0`).
2. Model-provider traffic is allowed by default; disable it with `PI_DOCKER_NETWORK_NONE=1` when needed.
3. For strict egress control, combine this with your enterprise proxy/firewall egress allowlist.
4. Credentials are intentionally persisted in Docker volume `secure-pi-agent` for usability (one-time `/login`), while keeping them out of images.

## Zero-trust level vs UX: current decision

This project uses a **balanced zero-trust profile** by default: strong runtime hardening and scoped access, while keeping login and daily usage friction low.

| Area | Security-first option | Current default (UX-oriented) | Rationale |
| --- | --- | --- | --- |
| Container egress | `PI_DOCKER_NETWORK_NONE=1` | Network enabled | Keep out-of-box model/API usage working; strict mode remains one env toggle away. |
| Workspace writes | `PI_WORKSPACE_READONLY=1` | Workspace writable | Allow normal coding-agent edit workflows without extra setup. |
| Runtime user | `PI_CONTAINER_USER=10001:10001` | Host uid:gid (run script) / `1000:1000` (compose default) | Avoid UID/GID mismatch blocking edits in mounted repos. |
| Extensions/packages | `PI_DISABLE_EXTENSIONS=1` | Allowed | Keep `settings.json` packages usable by default; disable only for stricter trust boundaries. |
| Context files (`AGENTS.md`/`CLAUDE.md`) | `PI_ALLOW_CONTEXT_FILES=0` | Enabled | Preserve expected agent behavior in existing repos; can be disabled in stricter environments. |
| Bash tool | `PI_DISABLE_BASH_TOOL=1` | Enabled | Maintain full coding-agent utility for typical developer tasks; disable when command execution must be restricted. |
| Auth persistence | Ephemeral auth per run | Persist in `secure-pi-agent` volume (self-contained; no host `~/.pi` dependency) | One-time `/login` and seamless reuse across runs. |

**Summary:** default posture is hardened and enterprise-appropriate for most teams, but not maximum isolation by default. For stricter zero-trust operation, enable the hardening toggles above (especially `PI_DOCKER_NETWORK_NONE=1`) and pair with org-level egress controls.
