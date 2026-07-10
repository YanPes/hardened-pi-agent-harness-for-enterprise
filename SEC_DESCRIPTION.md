# Security Description — zero-trust-pi-agent-harness

Detailed security audit reference for security teams reviewing the `zero-trust-pi-agent-harness` deployment. Covers runtime hardening, filesystem isolation, network controls, identity, credential handling, and the agent capability model.

---

## 1. What this tool is

`zero-trust-pi-agent-harness` wraps the [`pi`](https://pi.dev/) coding agent in a hardened Docker container. Its purpose is to constrain the agent's access to exactly one host repository while enforcing strong runtime isolation, so that the blast radius of any misbehaviour — intentional or not — is bounded by the container boundary.

---

## 2. Container runtime hardening

### 2.1 Read-only root filesystem

```
--read-only
```

The container root filesystem is mounted read-only at runtime. No process inside the container can modify system binaries, configuration files, or anything outside the explicitly permitted writable locations listed in §3.

### 2.2 Linux capabilities

```
--cap-drop ALL
```

All POSIX capabilities are dropped before the container process starts. No capabilities are added back. This prevents privilege escalation via capability abuse (e.g. `CAP_NET_RAW`, `CAP_SYS_ADMIN`, `CAP_DAC_OVERRIDE`).

### 2.3 Privilege escalation prevention

```
--security-opt no-new-privileges:true
```

Prevents any process inside the container from gaining new privileges via `setuid`/`setgid` binaries or filesystem capabilities, even if such binaries exist inside the image.

### 2.4 Resource limits

| Resource | Limit | Where set |
|---|---|---|
| Memory | 4 GB | `--memory 4g` / `mem_limit: 4g` |
| CPUs | 2 | `--cpus 2` / `cpus: 2.0` |
| PIDs | 512 | `--pids-limit 512` / `pids_limit: 512` |
| `/tmp` tmpfs | 256 MB, `noexec`, `nosuid` | `--tmpfs /tmp:rw,noexec,nosuid,size=256m` |
| `/run` tmpfs | 4 MB, `noexec`, `nosuid`, `uid=0`, `mode=0700` | `--tmpfs /run:rw,noexec,nosuid,uid=0,gid=0,mode=0700,size=4m` |

PID limits bound fork-bomb style resource exhaustion. Memory and CPU limits prevent the container from starving host workloads. Both tmpfs mounts are `noexec` — binaries cannot be dropped and executed there.

---

## 3. Filesystem access

### 3.1 Writable locations

| Path | Type | Purpose |
|---|---|---|
| `/workspace` | Bind mount (host repo) | The single repository the agent operates on |
| `/pi-agent` | Named Docker volume (`secure-pi-agent`) | Agent state: auth token, settings, installed packages |
| `/tmp` | tmpfs (noexec, nosuid, 256 MB) | Temporary scratch space |
| `/run` | tmpfs (noexec, nosuid, 4 MB, root-owned 0700) | Runtime sockets / PID files |

Everything else is read-only. The agent cannot write to system paths, the `pi` installation at `/opt/pi`, or any other host-mounted directory.

### 3.2 Repository scoping

Only the single path passed at invocation is bind-mounted to `/workspace`. No other host directory is accessible inside the container. The agent has no path to traverse to host home directories, system files, or sibling repositories.

### 3.3 Workspace write mode

Default: read-write (agent can edit files in the repo).  
Strict mode: `PI_WORKSPACE_READONLY=1` makes the bind mount read-only — the agent can inspect but not modify the repository.

### 3.4 Volume permissions

At startup a short-lived root container normalises `/pi-agent` permissions to `1777`. This is the only moment a root-privileged container runs; it has no network access, no capability additions, and exits immediately before the hardened main container starts.

---

## 4. Network

Default: outbound network is **enabled**. This is required for LLM API calls (model provider traffic).

Toggle to disable all outbound and inbound network:

```bash
PI_DOCKER_NETWORK_NONE=1 pi /path/to/repo
```

This passes `--network none` to `docker run`, severing all network access. Use this when the agent must not be able to exfiltrate data or reach external services, and when your LLM calls are proxied separately.

For fine-grained egress control (allowlisting model provider endpoints, blocking everything else), pair the default network mode with an organisation-level egress proxy or firewall rule applied to the Docker bridge interface.

---

## 5. User identity

### 5.1 Runtime user

The main container runs as the invoking host user (`$(id -u):$(id -g)` in `run-secure-pi.sh`, `${PI_CONTAINER_USER:-1000:1000}` in Compose). This is intentional: it avoids UID/GID mismatches that would make files written to `/workspace` unreadable or unwritable by the host user after the container exits.

Override explicitly:

```bash
PI_CONTAINER_USER=10001:10001 pi /path/to/repo   # fixed non-root service identity
PI_CONTAINER_USER=0:0 pi /path/to/repo           # root (only if explicitly required)
```

### 5.2 Image build identity

| UID:GID | Name | Used where |
|---|---|---|
| `0:0` | `root` | Package installation during image build only |
| `10001:10001` | `pi` | Owns `/opt/pi`, `/opt/pi-secure`, `/opt/pi-agent-seed`; runs `npm install` during build |

The `pi` user (uid 10001) is a dedicated non-root service account created in the Dockerfile. It owns the baked-in `pi` installation and is not used as the default runtime user (see §5.1).

### 5.3 Entrypoint switch

The `ENTRYPOINT` is `pi-secure-entrypoint` (a shell script at `/usr/local/bin/pi-secure-entrypoint`, mode `0755`). It does not call `su`, `sudo`, or `gosu` to switch users — identity is set by Docker's `--user` flag before the entrypoint runs.

---

## 6. Telemetry and update suppression

All three controls are set both in the image (`ENV` layer) and injected at runtime (`-e`) to ensure they cannot be accidentally overridden by a stale image layer:

| Control | Value | Effect |
|---|---|---|
| `PI_TELEMETRY` | `0` | Disables usage telemetry reporting |
| `PI_SKIP_VERSION_CHECK` | `1` | Prevents startup version-check HTTP calls |
| `PI_OFFLINE` | `1` | Disables all startup network probes by the pi runtime itself |
| `enableInstallTelemetry` | `false` | Set in `config/settings.json`; disables install-time telemetry |

---

## 7. Agent capability model

### 7.1 Tool allowlist

By default the agent has access to all built-in pi tools: `bash`, `read`, `edit`, `write`, `grep`, `find`, `ls`.

When `PI_DISABLE_BASH_TOOL=1` is set, the entrypoint passes `--tools read edit write grep find ls` to `pi`, removing the `bash` tool. The agent can still read, search, and write files — it cannot execute arbitrary shell commands.

> **Note:** even with `PI_DISABLE_BASH_TOOL=1`, the agent can read sensitive files inside `/workspace` (e.g. `.env`, key files) using the `read` tool. Combine with `PI_WORKSPACE_READONLY=1` and careful repository scoping to limit exposure.

### 7.2 Themes

Themes are disabled unconditionally via `--no-themes` in the entrypoint. This is not user-configurable at runtime.

### 7.3 Extensions / packages

Enabled by default and **required** — `settings.json` declares a mandatory package (`pi-forgeflow`) that must load for the agent to function correctly. Setting `PI_DISABLE_EXTENSIONS=1` passes `--no-extensions` to `pi` and prevents this package from loading. Only disable if you are fully replacing the default package set.

### 7.4 Context files

`AGENTS.md` and `CLAUDE.md` loading is **enabled** by default (`PI_ALLOW_CONTEXT_FILES=1`). Set `PI_ALLOW_CONTEXT_FILES=0` to pass `--no-context-files` and prevent the agent from reading project-level instruction files.

---

## 8. Credential and auth handling

| Property | Detail |
|---|---|
| Storage location | Named Docker volume `secure-pi-agent`, mounted at `/pi-agent` |
| Host involvement | None — `~/.pi` on the host is never read or written |
| Persistence | Token survives container restarts; volume must be explicitly removed to purge credentials |
| First-time auth | User runs `/login` inside the agent on first use; token is written to the volume |
| CI/CD pre-seeding | Set `PI_AUTH_JSON_BASE64` (base64-encoded `auth.json`) in the environment; entrypoint decodes and writes it to `/pi-agent/auth.json` only if no token already exists |
| Volume removal | `npx github:yanpes/zero-trust-pi-agent-harness clean` removes the volume and all stored credentials |

Credentials are never baked into the image and never touch the host filesystem.

---

## 9. Image provenance and supply chain

### 9.1 Base image

AMD64 builds use a SHA256-pinned base image by default:

```dockerfile
ARG NODE_BASE_IMAGE_AMD64=node:22-bookworm-slim@sha256:a149cd71dccd68704a07d4e4ca3e610c27301852b0f556865cfdb6e2856f8bed
```

ARM64 builds default to a floating tag (`node:22-bookworm-slim`). To pin ARM64:

```bash
docker build \
  --build-arg TARGETARCH=arm64 \
  --build-arg NODE_BASE_IMAGE_ARM64=node:22-bookworm-slim@sha256:<digest> \
  --platform linux/arm64 \
  -t secure-pi:arm64 .
```

### 9.2 Pi version

The `pi` npm package is installed at a pinned version (`PI_VERSION`, default `0.74.0`). Override at build time:

```bash
docker build --build-arg PI_VERSION=0.75.0 -t secure-pi:0.75.0 .
```

### 9.3 OS packages

The following packages are installed into the image during build: `bash`, `ca-certificates`, `git`, `gosu`, `openssh-client`, `fd-find`, `ripgrep`. No other packages are added. The `apt` cache is purged after install (`rm -rf /var/lib/apt/lists/*`).

---

## 10. Security toggle reference

| Variable | Default | Effect when changed |
|---|---|---|
| `PI_DOCKER_NETWORK_NONE` | `0` (network on) | `=1` → `--network none`, full network isolation |
| `PI_WORKSPACE_READONLY` | `0` (writable) | `=1` → workspace bind mount becomes read-only |
| `PI_DISABLE_BASH_TOOL` | `0` (enabled) | `=1` → agent loses `bash` tool; file tools remain |
| `PI_DISABLE_EXTENSIONS` | `0` (enabled, required) | `=1` → `--no-extensions` passed to pi; breaks mandatory `pi-forgeflow` package |
| `PI_ALLOW_CONTEXT_FILES` | `1` (enabled) | `=0` → `--no-context-files` passed to pi |
| `PI_CONTAINER_USER` | Host `uid:gid` | Override runtime container user identity |
| `PI_MEMORY_LIMIT` | `4g` | Override container memory cap |
| `PI_CPU_LIMIT` | `2` | Override container CPU cap |
| `PI_PIDS_LIMIT` | `512` | Override container PID cap |

---

## 11. What this setup does not cover

The following are **out of scope** for this harness and must be handled at the infrastructure level:

- **Egress allowlisting** — model provider traffic is allowed by default; enterprise environments should apply egress proxy or firewall rules to restrict outbound destinations
- **Image vulnerability scanning** — scan the built image with your organisation's preferred tool (Trivy, Grype, etc.) before deploying
- **Secrets in the repository** — the agent can read any file in `/workspace`; ensure the mounted repository does not contain unencrypted secrets unless intentional
- **Docker daemon security** — this harness assumes a trusted Docker daemon; rootless Docker or a hardened daemon configuration is recommended in production environments
- **Audit logging** — container-level command logging is not configured; integrate with your Docker logging driver and SIEM for audit trails
