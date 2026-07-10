# zero-trust-pi-agent-harness

Hardened Docker wrapper for [`pi`](https://pi.dev/) — runs your coding agent in a locked-down container with secure defaults, scoped to a single repository.

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running
- Node.js ≥ 18 (for `npx`)

---

## Install

```bash
npx github:yanpes/zero-trust-pi-agent-harness
```

This will:

1. Copy the harness to `~/.local/share/secure-pi`
2. Create a `secure-pi` binary at `~/.local/bin/secure-pi`
3. Add a `pi` shell alias to your shell config (`bash`, `zsh` and `fish` are supported)
4. Pre-build the Docker image so your first run is instant

**Restart your shell** (or source your config file), then you're ready.

> **Docker permission error?** If you see `permission denied` when connecting to the Docker daemon, add your user to the `docker` group and re-login:
>
> ```bash
> sudo usermod -a -G docker $USER
> ```
>
> Then log out and back in (or run `newgrp docker`) for the change to take effect.

---

## Usage

Run `pi` from inside any repo:

```bash
cd /path/to/your/repo
pi
```

Or point it at a repo directly:

```bash
pi /path/to/your/repo
```

You can use it headless as well - Pass a prompt inline:

```bash
pi /path/to/your/repo -p "summarize this codebase"
pi /path/to/your/repo -p "find dead code"
```

On first run, type `/login` inside the agent to authenticate with your pi.dev account. Your credentials are stored in a Docker volume — you only need to do this once.

---

## Uninstall

```bash
npx github:yanpes/zero-trust-pi-agent-harness clean
```

Removes the local install, shell alias, Docker image, and Docker volume. Add `--yes` to skip confirmation prompts:

```bash
npx github:yanpes/zero-trust-pi-agent-harness clean --yes
```

---

## Security toggles

All hardening is on by default. Optionally tune behaviour with environment variables:

| Variable | Effect |
|---|---|
| `PI_DOCKER_NETWORK_NONE=1` | Block all outbound network from the container |
| `PI_WORKSPACE_READONLY=1` | Mount your repo as read-only |
| `PI_DISABLE_BASH_TOOL=1` | Remove the agent's `bash` tool — bash is **enabled by default**; file tools (`read`, `grep`, `find`, `ls`) remain active regardless |
| `PI_DISABLE_EXTENSIONS=1` | Disable pi extensions / packages — **note:** this also prevents the mandatory `pi-forgeflow` package in `settings.json` from loading |
| `PI_ALLOW_CONTEXT_FILES=0` | Ignore `AGENTS.md` / `CLAUDE.md` in the repo |

Example:

```bash
PI_DOCKER_NETWORK_NONE=1 pi /path/to/your/repo
```

---

## Zero-trust level vs UX: current defaults

This project uses a **balanced zero-trust profile**: strong runtime hardening and scoped access, while keeping daily usage friction low.

| Area | Security-first option | Current default | Rationale |
|---|---|---|---|
| Container egress | `PI_DOCKER_NETWORK_NONE` | Network enabled | Keep out-of-box model/API usage working; strict mode is one toggle away. |
| Workspace writes | `PI_WORKSPACE_READONLY` | Workspace writable | Allow normal coding-agent edit workflows without extra setup. |
| Bash tool | `PI_DISABLE_BASH_TOOL` | **Enabled** | Full coding-agent utility; blast radius is contained by Docker hardening — read-only rootfs, dropped caps, scoped mounts. |
| Extensions/packages | `PI_DISABLE_EXTENSIONS` | **Enabled (required)** | `settings.json` declares a mandatory package (`pi-forgeflow`); disabling extensions prevents it from loading and breaks expected agent behaviour. Only disable if you are replacing the default package set entirely. |
| Context files | `PI_ALLOW_CONTEXT_FILES` | Enabled | Preserve expected agent behaviour in existing repos. |
| Auth persistence | Ephemeral auth per run | Persisted in `secure-pi-agent` Docker volume | One-time `/login`; no host `~/.pi` involvement. |

> **Summary:** the default posture is hardened and enterprise-appropriate for most teams. For maximum isolation, layer on `PI_DOCKER_NETWORK_NONE` and your org-level egress controls.

---

## What's enforced out of the box

- Container root filesystem is **read-only**
- All Linux capabilities **dropped**
- No privilege escalation (`no-new-privileges: true`)
- CPU, memory, and PID limits applied
- Telemetry and update checks disabled
- Only your target repository is mounted — nothing else on your host is accessible

For a full technical breakdown covering runtime flags, filesystem access, network controls, identity, credential handling, and supply chain — see **[SEC_DESCRIPTION.md](./SEC_DESCRIPTION.md)**.
