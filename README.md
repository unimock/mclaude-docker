# mclaude-docker

Runs [Claude Code](https://claude.ai/code) in a **persistent** container with SSH access.
Built on [`unimock/mclaude`](https://github.com/unimock/mclaude), which holds the image, the host launcher `mclaude` and the per-call wrapper mode.

- **Same image base:** Claude Code, tools and user setup come from `unimock/mclaude:<version>`; this repo only adds sshd and a keepalive entrypoint.
- **Correct ownership:** the container runs as your host UID/GID and user/group names.
- **One workspace:** a whole workspace root (many projects) is mounted at the same path.

## Quick facts

| | |
|---|---|
| Image | `unimock/mclaude-docker:<version>` (linux/amd64, linux/arm64), `FROM unimock/mclaude:<version>` |
| Version | = base image tag = bundled Claude Code release (file `VERSION`) |
| Run | `docker compose up -d`, then SSH or `docker compose exec` |
| State | `~/.mclaude/` on the host, area `~/.mclaude/area/longrunning/` |
| Requires | Docker + Compose plugin on the host |
| Not | a sandbox (passwordless sudo inside, Docker socket always mounted) |

## Security

The container user has passwordless sudo, and the workspace is writable.
The host's Docker socket is **always** mounted (see `docker-compose.yml`): anything running in the container can start privileged containers and thus act as root on the host.
Treat the container with the same trust as running Claude Code directly on the host.

## Setup

**1. Configure:** edit these literals in `docker-compose.yml` (the workspace path appears 3×):

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

Defaults: `TZ=UTC`, `hostname=mclaude`, SSH port `2222`.

**2. State:** create the area `longrunning` and the shared Claude state:

```bash
mkdir -p ~/.mclaude/.claude
touch ~/.mclaude/.claude.json                         # must be a FILE
mkdir -p -m 700 ~/.mclaude/area/longrunning/{.ssh,.docker,sshd}
cp ~/.gitconfig ~/.mclaude/area/longrunning/.gitconfig  # must be a FILE (or touch it)
cat ~/.ssh/id_ed25519.pub >> ~/.mclaude/area/longrunning/sshd/authorized-keys
```

- Files that don't exist before the first start are created by Docker as root-owned **directories**, and claude/git fail to use them.
- The area has no `area.conf`, so the host launcher `mclaude` never selects it.

**3. Run:**

```bash
docker compose up -d
ssh -p 2222 youruser@<docker-host>                 # lands in the workspace
docker compose exec -u youruser mclaude bash       # alternative without SSH
claude                                             # inside; `mclaude` is an alias
docker compose down
```

## SSH access

- Public key only: no passwords, no root. Only `CLAUDE_USER` may log in.
- Host keys are generated on first start and persisted (stable identity, no host-key warnings).
- Key changes are read on the next login; no restart needed.
- Without any key in `authorized-keys`, login is refused (a warning is logged).

## State

| Host | Container | Content |
|---|---|---|
| `~/.mclaude/.claude/` | `/home/claude/.claude/` | Claude config, memory, sessions (shared with `mclaude`) |
| `~/.mclaude/.claude.json` | `/home/claude/.claude.json` | Login/OAuth, onboarding, projects, MCP (shared with `mclaude`) |
| `~/.mclaude/area/longrunning/.ssh/` | `/home/claude/.ssh/` | SSH client keys. `id_ed25519` is generated if missing (see `docker compose logs`). |
| `~/.mclaude/area/longrunning/.docker/` | `/home/claude/.docker/` | Docker client config, `docker login` credentials (base64, not encrypted) |
| `~/.mclaude/area/longrunning/.gitconfig` | `/home/claude/.gitconfig` | git identity |
| `~/.mclaude/area/longrunning/sshd/` | `/home/claude/.mclaude/sshd/` | `hostkeys/` (generated), `authorized-keys` (you add them) |
| workspace | same path | Project files |

In `docker compose exec` shells, `$MCLAUDE_AREA` is `longrunning` (SSH sessions don't inherit the container env).

## Migration from the old layout

The former all-in-one mclaude-docker used global paths. Stop the old container, move them into the area (instead of setup step 2), then start the new image:

```bash
docker compose down                   # old container
A=~/.mclaude/area/longrunning
mkdir -p -m 700 $A/.ssh $A/.docker $A/sshd
mv ~/.mclaude/.longrunning/* $A/sshd/ && rmdir ~/.mclaude/.longrunning
cp -pR ~/.mclaude/.ssh/. $A/.ssh/     # keeps the key registered at GitHub & co.
cp -pR ~/.mclaude/.docker/. $A/.docker/
cp -p ~/.mclaude/.gitconfig $A/.gitconfig
docker compose pull && docker compose up -d
```

The host launcher and `~/.mclaude/trusted_areas` now belong to [mclaude](https://github.com/unimock/mclaude) (areas in `~/.mclaude/area/<name>/area.conf`).

## Repository

| File | Role |
|---|---|
| `Dockerfile` | `FROM unimock/mclaude:<VERSION>` + openssh-server, `mclaude` → `claude` alias |
| `mclaude-longrunning` | Entrypoint: sources the base image's `/usr/local/lib/mclaude/setup.sh` (user mapping, sudo, docker group, SSH key), starts sshd, keeps the container alive |
| `sshd_config.mclaude` | Self-contained sshd config: key-only, no root, keys from `/home/claude/.mclaude/sshd` |
| `docker-compose.yml` | The long-running service: workspace, state, Docker socket, port `2222` |
| `docker-bake.hcl` | Tags and build args. Targets `mclaude-docker` (host arch) and `release` (amd64 + arm64). |
| `push.sh` | Builds and pushes `release` as `:latest` + `:$VERSION` |
| `VERSION` | The `unimock/mclaude` tag to build on, e.g. `2.1.314` |

## Build & release

Release [mclaude](https://github.com/unimock/mclaude) first, then:

```bash
cp ../mclaude/VERSION VERSION                # same version as the base image
export VERSION="$(cat VERSION)" BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
docker buildx bake --load                    # local build, host arch
docker login && ./push.sh                    # multi-arch build + push :latest and :$VERSION
docker compose pull && docker compose up -d  # roll out
```

- `push.sh` reads `VERSION` itself and refuses to push unless `unimock/mclaude:$VERSION` exists and bake resolved `:$VERSION`.
- Without `VERSION`, bake builds on `unimock/mclaude:latest` and tags `:latest`.

## Adding dependencies

- Permanent: add the package to the `RUN` block in the `Dockerfile` (or to mclaude's, for both images), then rebuild.
- Runtime (lost on container recreate): `sudo apt-get update && sudo apt-get install <pkg>`, `npm install -g <pkg>`, `python3 -m venv ~/.venv`.

## License

MIT, see `LICENSE`.
