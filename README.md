# mclaude

Thin Docker wrapper that runs [Claude Code](https://claude.ai/code) in an isolated Debian container.

- **Clean host** – Node.js, npm and the CLI stay in the container.
- **Correct ownership** – writes use the host UID/GID, no root-owned files.

## Two modes

Same image, same `claude-wrapper` entrypoint, same state under `~/.mclaude/`. They can coexist.

| | **Wrapper mode** (default) | **Long-running mode** |
|---|---|---|
| How | One `docker run --rm` per invocation | Persistent container (`docker compose up -d`) |
| Invoke | `mclaude` on the **host** | `claude` **inside** the container |
| Lifetime | Per command | Until `docker compose down` |
| Scope | Current dir (`$PWD`) | A workspace root (many projects) |
| For | Quick throwaway runs | Interactive sessions |

## Requirements

- Docker + Compose plugin (`docker compose`)
- A Claude Code login token (created on first run)

## Installation

Deploy the launcher; it pulls the image tag it pins (`unimock/mclaude:<version>`) from Docker Hub on first run:

```bash
sudo install -pm755 mclaude /usr/local/bin/mclaude
```

**Update / uninstall:** redeploy the launcher (same command) / `sudo rm /usr/local/bin/mclaude`.
Building the image yourself: see [Versioning](#versioning) / [Multi-arch builds](#multi-arch-builds).

## Wrapper mode (default)

Run `mclaude` instead of `claude` from any project directory:

```bash
cd ~/projects/my-project
mclaude
mclaude --help
echo "Summarize the README" | mclaude -p      # args + piped input pass through to claude
```

Refuses to start from `$HOME` (avoids mounting your whole home).

## Long-running mode

**1. Configure** — edit these literals in `docker-compose.yml` (workspace path appears 3×):

```yaml
    working_dir: /home/youruser/MyGits
    environment:
      CLAUDE_WORKDIR: /home/youruser/MyGits   # = working_dir
      CLAUDE_UID: "1000"                       # id -u
      CLAUDE_GID: "1000"                       # id -g
    volumes:
      - /home/youruser/MyGits:/home/youruser/MyGits
```

Workspace is mounted at the **same path** inside the container. Defaults: `TZ=UTC`, `hostname=mclaude`, SSH port `2222`.

**2. State** (auto-created by wrapper mode; otherwise):

```bash
mkdir -p ~/.mclaude/.claude
```

**3. Run:**

```bash
docker compose up -d
docker compose exec -u claude mclaude bash    # land in the workspace, then run `claude`
docker compose down
```

Inside the container use `claude` directly; the host `mclaude` launcher is wrapper-mode only.

### SSH access

Pre-shared-key only — no passwords, no root.

```bash
mkdir -p ~/.mclaude/.longrunning
cat ~/.ssh/id_ed25519.pub >> ~/.mclaude/.longrunning/authorized-keys
docker compose up -d                          # picks up the key
ssh -p 2222 claude@<docker-host>
```

Host keys are generated on first start and persisted (stable identity, no host-key warnings).

| Host path                                 | Purpose                               |
|-------------------------------------------|---------------------------------------|
| `~/.mclaude/.longrunning/hostkeys/`       | sshd host keys (auto-generated)       |
| `~/.mclaude/.longrunning/authorized-keys` | authorized public keys (you add them) |

## Common commands

| Command | Description |
|---------|-------------|
| `docker compose build` | Build `unimock/mclaude:latest` (host arch) |
| `docker compose up -d` | Start the long-running container |
| `docker compose down` | Stop and remove it |
| `docker compose exec -u claude mclaude bash` | Shell into the running container |
| `docker compose run --rm mclaude bash` | One-off throwaway shell |
| `docker buildx bake --push` | Build+push multi-arch (see below) |

## Multi-arch builds

Platforms live in `build.x-bake.platforms` of `docker-compose.yml`.

- **Local** — `docker compose build`: host arch only, loaded as `unimock/mclaude:latest`. (The local store can't hold a multi-platform image; multi-arch must target a registry.)
- **Distribution** — `docker buildx bake --push`: both arches as one manifest, pushed to Docker Hub as `unimock/mclaude` (foreign arch via QEMU emulation).

```bash
docker login
docker buildx create --name mclaude-builder --driver docker-container --bootstrap --use
export VERSION="$(cat VERSION)"
docker buildx bake --push                     # pushes :latest + :$VERSION
```

Tags, build args and platforms come from `docker-compose.yml`. Set the version vars ([Versioning](#versioning)) first; edit `tags` to push under a different name. For a full release (build+push **and** stamp the launcher), use `./release.sh` — see [Versioning](#versioning).

## Architecture

- **`mclaude`** (host launcher, `/usr/local/bin`) — refuses `$HOME`; bind-mounts `$PWD` at the same path; passes `CLAUDE_UID`/`CLAUDE_GID`; mounts `~/.mclaude/.claude` and the Docker socket; allocates a TTY only when interactive.
- **`claude-wrapper`** (container entrypoint) — sets the `claude` UID/GID, adds it to the Docker-socket group, re-chowns npm globals, `cd`s into `CLAUDE_WORKDIR`, exec's `claude`. With `--keepalive` (long-running) it instead starts sshd and keeps the container alive (`tail -f /dev/null`).
- **`docker-compose.yml`** (long-running service) — runs `claude-wrapper --keepalive`, mounts the workspace and the same state/socket as wrapper mode, forwards port `2222`. Workspace path, UID/GID and SSH port are literals in the file (no `.env`).
- **`sshd_config.mclaude`** — self-contained sshd config: key-only, no root, `AllowUsers claude`, keys read from `~/.mclaude/.longrunning`.
- **`release.sh`** — build+push the multi-arch image to Docker Hub and stamp the version into the launcher; run after bumping `VERSION`.
- **`Dockerfile`** — `debian:trixie-slim`; Node.js, npm, git, ripgrep, fd-find, jq, Docker CLI, openssh-client/server, vim, python3(+pip/venv), g++, shellcheck; Claude Code via `npm install -g`; `claude` owns npm globals; passwordless sudo; `~/.local/bin/claude` symlink for `/doctor`.

## State and configuration

| Host path                  | Container path                        | Purpose                         |
|----------------------------|---------------------------------------|---------------------------------|
| `~/.mclaude/.claude/`      | `/home/claude/.claude/`               | Config, memory, sessions        |
| `~/.gitconfig`             | `/home/claude/.gitconfig`             | Git identity                    |
| `~/.mclaude/.longrunning/` | `/home/claude/.mclaude/.longrunning/` | sshd keys + authorized-keys     |
| `$PWD`                     | `$PWD` (same path)                    | Project files                   |

All state lives under `~/.mclaude/` on the host and persists across runs.

## Versioning

Single source of truth: the **`VERSION`** file (SemVer, e.g. `0.1.1`) — no git involved. Two
build vars read by `docker-compose.yml`:

| Variable | Used for | Default |
|----------|----------|---------|
| `VERSION` | image tag, `MCLAUDE_VERSION` env var + OCI `version` label | `dev` |
| `BUILD_DATE` | `org.opencontainers.image.created` label | `unknown` |

```bash
export VERSION="$(cat VERSION)"
export BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
docker compose build                          # tags :latest + :$VERSION
```

The `mclaude` launcher carries the same version (top of the script) and pins the image tag it
runs (`unimock/mclaude:<VERSION>`). Wrapper-mode users are updated **only** by redeploying it.

**Release** — bump `VERSION`, then run `release.sh` (needs `docker login`):

```bash
./release.sh                                  # build+push multi-arch image, stamp mclaude
git commit -am "release $(cat VERSION)" && git tag "v$(cat VERSION)"
```

`release.sh` pushes `unimock/mclaude:<VERSION>` + `:latest` and rewrites the launcher's
`MCLAUDE_VERSION`. Wrapper users then update with `sudo install -pm755 mclaude /usr/local/bin/mclaude`.

```bash
mclaude --mclaude-version                     # baked-in value, e.g. mclaude 0.1.1
mclaude --version                             # (no mclaude- prefix) Claude Code's own version
```

## Adding dependencies

Permanent — add to the first `RUN` block in the `Dockerfile`, then `docker compose build` (or `docker buildx bake --push`).

Runtime (lost on container recreate; `claude` has passwordless sudo):

```bash
sudo apt-get update && sudo apt-get install <pkg>          # apt: update first
npm install -g <pkg>                                        # npm globals: no sudo
python3 -m venv ~/.venv && ~/.venv/bin/pip install <pkg>    # pip: PEP 668-safe
sudo pip3 install --break-system-packages <pkg>             # pip: system-wide
```
