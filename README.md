# mclaude

Thin Docker wrapper that runs [Claude Code](https://claude.ai/code) in an isolated Debian container.

- **Clean host** – Node.js, npm and the CLI stay in the container.
- **Correct ownership** – writes use the host UID/GID, no root-owned files.
- **Host identity** – inside, the user and group carry the host's names (e.g. `mok:mok`), home stays `/home/claude`.

## Two modes

Same image, same `claude-wrapper` entrypoint, same state under `~/.mclaude/`. They can coexist.

| | **Wrapper mode** (default) | **Long-running mode** |
|---|---|---|
| How | One `docker run --rm` per invocation | Persistent container (`docker compose up -d`) |
| Invoke | `mclaude` on the **host** | `claude` **inside** the container |
| Lifetime | Per command | Until `docker compose down` |
| Scope | Current dir (`$PWD`) | A workspace root (many projects) |
| For | Quick throwaway runs | Interactive sessions |

## Security

mclaude keeps your host **clean**, it is **not a sandbox**. The container user has passwordless
sudo inside the container, and everything below the mounted directory is writable.

The host's Docker socket is **not** mounted by default. A [trusted area](#trusted-areas) or
`mclaude --mclaude-docker` can opt in to it (see [Docker inside mclaude](#docker-inside-mclaude)). With the socket, anything
running in the container can start privileged containers and thus act as root on the host.
Treat such an area with the same trust as running Claude Code directly on the host. The
long-running container always gets the socket (see `docker-compose.yml`).

## Requirements

- Docker + Compose plugin (`docker compose`)
- A Claude Code login token (created on first run)

## Installation

Deploy the launcher; it pulls the image tag it pins (`unimock/mclaude:<version>`) from Docker Hub on first run.

**Install / update — straight from `main`** (one line, no clone):

```bash
curl -fsSL https://raw.githubusercontent.com/unimock/mclaude-docker/main/mclaude | sudo install -pm755 /dev/stdin /usr/local/bin/mclaude
```

Or from a checkout: `sudo install -pm755 mclaude /usr/local/bin/mclaude`. **Uninstall:** `sudo rm /usr/local/bin/mclaude`.
Building and publishing the image yourself: see [Versioning & multi-arch builds](#versioning--multi-arch-builds).

## Wrapper mode (default)

Run `mclaude` instead of `claude` from any project directory:

```bash
cd ~/projects/my-project
mclaude
mclaude --help
echo "Summarize the README" | mclaude -p      # args + piped input pass through to claude
mclaude --mclaude-docker                      # this run: mount Docker socket + ~/.mclaude/.docker
mclaude --mclaude-host-network                # this run: docker run --network host
mclaude --mclaude-version                     # wrapper/image version (--version is claude's)
```

Refuses to start from `$HOME` (avoids mounting your whole home).

### Trusted areas

By default only `$PWD` is mounted. To give Claude a wider view, list "trusted areas" in
`~/.mclaude/trusted_areas`. One area per line, fields separated by `|` (trailing fields optional),
`#` comments and blank lines ignored:

```
# path          | extra docker run args
~/MyGits        | -v /var/run/docker.sock:/var/run/docker.sock -v ~/.mclaude/.docker:/home/claude/.docker -v ~/.mclaude/.gitconfig:/home/claude/.gitconfig
~/web           | -p 8080:8080 -e FOO=bar
/srv/my work    | --network host
~/customer-x    | -v ~/.mclaude/gitconfig.customer-x:/home/claude/.gitconfig
~/scratch
```

- **path** — absolute, `~` allowed. If `$PWD` is the area or lies below it, the area is mounted
  (same path) while Claude still starts in `$PWD`. With nested areas the longest match wins;
  `/a/b` never matches `/a/bc`. An area of `/` or `$HOME` is refused. No match → just `$PWD`.
- **extra docker run args** — appended to `docker run` (before the image) when this area matches.
  Only the args of the winning (longest) match are used. They are split on whitespace; there is
  no quoting and no globbing, so values with spaces are not possible. A `~/` at the start of a
  word or right after `:` or `=` means `$HOME` (`-v ~/a:/b`, `--env=DIR=~/x`); nothing else is
  expanded.

`--mclaude-docker` and `--mclaude-host-network` add their mounts/flag on top of the area's args
(skipped where the area already has them, since Docker refuses duplicate mount points).

**Git config:** no `.gitconfig` is mounted by default, so git inside has no identity unless an
area mounts one, e.g. `-v ~/.mclaude/.gitconfig:/home/claude/.gitconfig` (seeded from
`~/.gitconfig` on first run) or a per-area file as for `~/customer-x` above. The source file
must exist before the run; otherwise Docker creates a root-owned directory in its place.

`|` must not appear in a path or an argument; further fields may be added later. On first run
`mclaude` creates the file as a commented-out template (no active entries). The former
`~/.mclaude/mount-roots` is no longer read.

### Docker inside mclaude

The Docker CLI (with the `buildx` and `compose` plugins) is in the image, but it only works
where the host's socket is mounted. Enable it per run with `mclaude --mclaude-docker`, or per
trusted area, together with the Docker client config that holds the registry credentials:

```
~/MyGits | -v /var/run/docker.sock:/var/run/docker.sock -v ~/.mclaude/.docker:/home/claude/.docker
```

To push to a registry, log in once **inside** the container. The credentials persist in
`~/.mclaude/.docker/config.json` on the host and are shared by all areas that mount it:

```bash
docker login                     # Docker Hub: use an access token, not your password
docker login registry.example.com
docker push unimock/foo:1.0      # or ./push.sh for multi-arch builds
```

The host's own `~/.docker` is deliberately not used: credential helpers such as `desktop`,
`pass` or `secretservice` don't exist in the container. Inside, `docker login` stores the
credentials **base64-encoded, not encrypted** (file mode 600). `mclaude` creates
`~/.mclaude/.docker/` with mode 700.

## Long-running mode

**1. Configure** — edit these literals in `docker-compose.yml` (workspace path appears 3×):

```yaml
    working_dir: /home/youruser/MyGits
    environment:
      CLAUDE_WORKDIR: /home/youruser/MyGits   # = working_dir
      CLAUDE_UID: "1000"                       # id -u
      CLAUDE_GID: "1000"                       # id -g
      CLAUDE_USER: youruser                    # id -un
      CLAUDE_GROUP: yourgroup                  # id -gn
    volumes:
      - /home/youruser/MyGits:/home/youruser/MyGits
```

Workspace is mounted at the **same path** inside the container. Defaults: `TZ=UTC`, `hostname=mclaude`, SSH port `2222`.

**2. State** (auto-created by wrapper mode; otherwise):

```bash
mkdir -p ~/.mclaude/.claude
touch ~/.mclaude/.claude.json     # must exist as a FILE before first start (see note below)
cp ~/.gitconfig ~/.mclaude/.gitconfig   # likewise a FILE (or touch it); wrapper mode does both automatically
mkdir -p ~/.mclaude/.ssh ~/.mclaude/.docker
```

**3. Run:**

```bash
docker compose up -d
docker compose exec -u youruser mclaude bash    # land in the workspace, then run `claude`
docker compose down
```

Inside the container use `claude` directly; the host `mclaude` launcher is wrapper-mode only.

### SSH access

Pre-shared-key only — no passwords, no root.

```bash
mkdir -p ~/.mclaude/.longrunning
cat ~/.ssh/id_ed25519.pub >> ~/.mclaude/.longrunning/authorized-keys
docker compose up -d                          # picks up the key
ssh -p 2222 youruser@<docker-host>   # the host user name (CLAUDE_USER)
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
| `docker compose exec -u youruser mclaude bash` | Shell into the running container |
| `docker compose run --rm mclaude bash` | One-off throwaway shell |
| `./push.sh` | Build+push multi-arch `:latest` + `:$VERSION` (see [below](#versioning--multi-arch-builds)) |

## Architecture

- **`mclaude`** (host launcher, `/usr/local/bin`) — refuses `$HOME`; bind-mounts `$PWD` (or its matching [trusted area](#trusted-areas), plus that area's extra `docker run` args) at the same path and starts claude in `$PWD`; passes `CLAUDE_UID`/`CLAUDE_GID`/`CLAUDE_USER`/`CLAUDE_GROUP`; creates and mounts `~/.mclaude/.claude`, `~/.mclaude/.claude.json`, `~/.mclaude/.ssh`; creates `~/.mclaude/.gitconfig` (seeded from `~/.gitconfig`) but mounts it only via a trusted area; the Docker socket and `~/.mclaude/.docker` only via a trusted area or `--mclaude-docker`, `--network host` via `--mclaude-host-network`; allocates a TTY only when interactive.
- **`claude-wrapper`** (container entrypoint) — sets the `claude` UID/GID and renames user/group to the host names (keeps `claude` if a name is invalid or already taken in the image; if the host GID already belongs to an image group, e.g. `100` = `users`, that group becomes the primary group), grants passwordless sudo, adds the user to the Docker-socket group, generates `~/.ssh/id_ed25519` if missing, re-chowns npm globals, `cd`s into `CLAUDE_WORKDIR`, exec's `claude`. With `--keepalive` (long-running) it instead starts sshd and keeps the container alive (`tail -f /dev/null`).
- **`docker-compose.yml`** (long-running service) — runs `claude-wrapper --keepalive`, mounts the workspace and the same state as wrapper mode plus, always, the Docker socket and `~/.mclaude/.docker`, forwards port `2222`. Workspace path, UID/GID, user/group names and SSH port are literals in the file (no `.env`).
- **`sshd_config.mclaude`** — self-contained sshd config: key-only, no root, `AllowUsers` = the host user (set by `claude-wrapper` at runtime), keys read from `~/.mclaude/.longrunning`.
- **`Dockerfile`** — `debian:trixie-slim`; Node.js, npm, git, ripgrep, fd-find, jq, Docker CLI (+buildx, compose), openssh-client/server, vim, python3(+pip/venv), g++, shellcheck, ping; Claude Code via `npm install -g`; `claude` owns npm globals; passwordless sudo; `~/.local/bin/claude` symlink for `/doctor`.

## State and configuration

| Host path                  | Container path                        | Purpose                         |
|----------------------------|---------------------------------------|---------------------------------|
| `~/.mclaude/.claude/`      | `/home/claude/.claude/`               | Config, memory, sessions        |
| `~/.mclaude/.claude.json`  | `/home/claude/.claude.json`           | Primary state: login/OAuth, onboarding, projects, MCP |
| `~/.mclaude/.gitconfig`    | `/home/claude/.gitconfig`             | Git identity (first run: copied from `~/.gitconfig`); wrapper mode: only where a trusted area mounts it |
| `~/.mclaude/.ssh/`         | `/home/claude/.ssh/`                  | SSH client keys; `id_ed25519` generated if missing — add `id_ed25519.pub` to GitHub & co. |
| `~/.mclaude/.docker/`      | `/home/claude/.docker/`               | Docker client config + registry creds (`docker login`); trusted area / `--mclaude-docker` / long-running only |
| `~/.mclaude/trusted_areas` | —                                     | Optional wrapper-mode [trusted areas](#trusted-areas) (read by `mclaude` on the host) |
| `~/.mclaude/.longrunning/` | `/home/claude/.mclaude/.longrunning/` | sshd keys + authorized-keys     |
| `$PWD` or trusted area     | same path                             | Project files                   |

All state lives under `~/.mclaude/` on the host and persists across runs.

> **Note — `~/.claude.json` must be a file, not a directory.** Claude Code keeps
> its primary state (login/OAuth, onboarding, projects, MCP servers) in
> `~/.claude.json`, a *sibling* of the `.claude/` directory — not inside it. It is
> mounted separately. Wrapper mode `touch`es it automatically; for long-running
> mode you must `touch ~/.mclaude/.claude.json` once before `docker compose up`.
> If it doesn't exist as a file, Docker auto-creates the bind-mount source as a
> **directory** and Claude Code fails to write its config.

## Versioning & multi-arch builds

mclaude has **no version of its own** — it tracks the [Claude Code](https://www.npmjs.com/package/@anthropic-ai/claude-code)
CLI release it bundles. The **`VERSION`** file is the single source of truth: it holds the exact
`@anthropic-ai/claude-code` version to install (e.g. `2.1.296`), which the Dockerfile pins and which
becomes the image tag, `MCLAUDE_VERSION` env var and OCI `version` label.

Two build vars read by `docker-compose.yml` carry it into the image:

| Variable | Used for | Default |
|----------|----------|---------|
| `VERSION` | pinned Claude Code release, image tag, `MCLAUDE_VERSION` env var + OCI `version` label | `dev` (installs latest) |
| `BUILD_DATE` | `org.opencontainers.image.created` label | `unknown` |

Tags, build args and platforms (`build.x-bake.platforms`) all live in `docker-compose.yml`. The
`mclaude` launcher carries the same version (top of the script) and pins the image tag it runs
(`unimock/mclaude:<VERSION>`). Building with no `VERSION` set (`dev`) installs the latest Claude Code
release instead of pinning one.

**1. Pick a Claude Code release** — find the latest with `npm view @anthropic-ai/claude-code version`,
write it into the `VERSION` file, then set the build vars:

```bash
export VERSION="$(cat VERSION)"
export BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

**2. Build locally** (host arch only, loaded into the local image store):

```bash
docker compose build                          # tags :latest + :$VERSION
```

The local store can't hold a multi-platform image, so multi-arch must target a registry — use
step 3 to publish.

**3. Build + push multi-arch** (both arches as one manifest, foreign arch via QEMU emulation):

```bash
docker login
./push.sh                                     # pushes :latest + :$VERSION to Docker Hub
```

`push.sh` sets `VERSION`/`BUILD_DATE` itself from the `VERSION` file (step 1's exports are only
needed for `docker compose build`), creates the `mclaude-builder` buildx builder if missing, and
refuses to push unless bake resolved the `:$VERSION` tag — a bare `docker buildx bake --push` in a
shell without `VERSION` would silently push `:latest` + `:dev`. Extra args go to `docker buildx bake`.

(Edit `tags` in `docker-compose.yml` to push under a different name.)

**4. Stamp + ship the launcher** so wrapper-mode users get this version — they update **only** by
redeploying it:

```bash
sed -i "s/^MCLAUDE_VERSION=.*/MCLAUDE_VERSION=\"${VERSION}\"/" mclaude
sudo install -pm755 mclaude /usr/local/bin/mclaude
```

Check the installed versions:

```bash
mclaude --mclaude-version                     # baked-in value, e.g. mclaude 2.1.296
mclaude --version                             # Claude Code's own version — now the same value
```

## Adding dependencies

Permanent — add to the first `RUN` block in the `Dockerfile`, then `docker compose build` (or `./push.sh`).

Runtime (lost on container recreate; the container user has passwordless sudo):

```bash
sudo apt-get update && sudo apt-get install <pkg>          # apt: update first
npm install -g <pkg>                                        # npm globals: no sudo
python3 -m venv ~/.venv && ~/.venv/bin/pip install <pkg>    # pip: PEP 668-safe
sudo pip3 install --break-system-packages <pkg>             # pip: system-wide
```
