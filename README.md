# Hardened Pi Agent Harness For Enterprise

Hardened Docker wrapper for `pi` (https://pi.dev/) suitable for zero-trust enterprise environments. `secure-pi` launches `pi` in a locked-down container with secure defaults, minimizing attack surface while maintaining core functionality for codebase and LLM interactions.

## What this setup enforces

- **Repo scoping**: only one host repository is mounted to `/workspace`
- **Read-only container root filesystem**: blocks writes outside mounted tmpfs + repo
- **Non-root runtime user**: runs as UID `10001` user `pi`
- **Dropped Linux capabilities**: `--cap-drop ALL`
- **No privilege escalation**: `no-new-privileges:true`
- **Constrained resources**: CPU, memory, PID limits
- **Telemetry and update checks disabled**:
  - `enableInstallTelemetry: false` (settings)
  - `PI_TELEMETRY=0`
  - `PI_SKIP_VERSION_CHECK=1`
  - `PI_OFFLINE=1` (disables startup network checks)
- **Untrusted dynamic resources disabled by default**:
  - `--no-extensions --no-themes`

> **Intentional UX/Security tradeoffs:**
>
> - `~/.pi` state (including auth) is persisted in dedicated Docker volume (`secure-pi-agent`) for plug-and-play startup without host file permission tuning. On `run-secure-pi.sh`, existing host auth at `~/.pi/agent/auth.json` is imported automatically on first run when available.
> - `Skills` and `prompt templates` are intentionally enabled for developer experience.

## Files

- `Dockerfile` - hardened `pi` image
- `docker/entrypoint.sh` - secure defaults + startup config bootstrap
- `config/settings.json` - telemetry-off base settings
- `run-secure-pi.sh` - all-in-one Linux/macOS wrapper (auto-build + run)
- `docker-compose.yml` - compose alternative

## Getting started

### Linux / macOS first-time setup

Before first run, make the wrapper executable:

```bash
chmod +x run-secure-pi.sh
```

What this does:

- Adds execute permission to `run-secure-pi.sh` so `./run-secure-pi.sh` works.

If you cloned files with Windows-style line endings, convert shell scripts to Unix line endings:

```bash
perl -pi -e 's/\r$//' run-secure-pi.sh docker/entrypoint.sh
```

What this does:

- Removes trailing `\r` characters from each line.
- Fixes errors like `/usr/bin/env: ‘bash\r’: No such file or directory`.
- Ensures shell shebangs work on Linux/macOS.

Then run Pi against repo:

```bash
./run-secure-pi.sh /absolute/path/to/repo
```

Optional: add a short shell alias in `~/.bashrc`:

```bash
alias secpi='/absolute/path/to/hardened-pi-agent-harness-for-enterprise/run-secure-pi.sh'
```

What this does:

- Lets you run `secpi /absolute/path/to/repo` instead of typing full script path.

Apply it:

```bash
source ~/.bashrc
```

## Build (optional)

The run scripts auto-build the image if it does not exist.

Manual build:

```bash
docker build -t secure-pi:latest .
```

Pin a specific Pi version:

```bash
docker build --build-arg PI_VERSION=0.42.0 -t secure-pi:0.42.0 .
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

- Disable outbound network (default allows network):

```bash
PI_DOCKER_NETWORK_NONE=1 ./run-secure-pi.sh /<path-to-repo>/
```

- Force workspace read-only (default is writable):

```bash
PI_WORKSPACE_READONLY=1 ./run-secure-pi.sh /<path-to-repo>/
```

- Override built-in Pi version pin:

```bash
PI_VERSION=0.42.0 ./run-secure-pi.sh /<path-to-repo>/
```

## Compose usage

Pi state (including auth) is persisted automatically in Docker volume `secure-pi-agent`.

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
| Context files (`AGENTS.md`/`CLAUDE.md`) | `PI_ALLOW_CONTEXT_FILES=0` | Enabled | Preserve expected agent behavior in existing repos; can be disabled in stricter environments. |
| Bash tool | `PI_DISABLE_BASH_TOOL=1` | Enabled | Maintain full coding-agent utility for typical developer tasks; disable when command execution must be restricted. |
| Auth persistence | Ephemeral auth per run | Persist in `secure-pi-agent` volume | One-time `/login` and seamless reuse across runs improves enterprise adoption and onboarding. |

**Summary:** default posture is hardened and enterprise-appropriate for most teams, but not maximum isolation by default. For stricter zero-trust operation, enable the hardening toggles above (especially `PI_DOCKER_NETWORK_NONE=1`) and pair with org-level egress controls.
