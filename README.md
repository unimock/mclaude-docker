# mclaude

`mclaude` is a thin Docker wrapper that runs [Claude Code](https://claude.ai/code) inside an isolated Debian container.

It solves two problems:

- **Clean host environment** – Claude Code's dependencies (Node.js, npm, the CLI itself) stay inside the container and never touch the host.
- **Correct file ownership** – all writes into your project happen with the host user's UID/GID, so no root-owned files are left behind.

## Two modes

`mclaude` can run in either of two modes. They share the same image, the same
`claude-wrapper` entrypoint, and the same persistent state under `~/.mclaude/`.

| | **Wrapper mode** (default) | **Long-running mode** |
|---|---|---|
| How it runs | One ephemeral `docker run --rm` per invocation | A persistent container started with `docker compose up -d` |
| You invoke | `mclaude` on the **host** | `claude` **inside** the container after `docker compose exec` |
| Lifetime | Container starts and exits per command | Container stays up until you `docker compose down` |
| Scope | The current project dir (`$PWD`) | A configurable workspace root (many projects) |
| Best for | Quick, isolated, throwaway runs | Logging in and working interactively for a while |

Both modes are described below. Pick whichever fits; they can coexist.

## Requirements

- Docker (with access to the Docker daemon)
- `make`
- A Claude Code login token (created on first run)

## Installation

```bash
make docker     # Build the mclaude:latest image
make install    # Install the launcher to /usr/local/bin/mclaude (uses sudo)
```

## Wrapper mode (default)

After installation, run `mclaude` instead of `claude` from any project directory:

```bash
cd ~/projects/my-project
mclaude
```

Each invocation spins up a fresh container, runs `claude`, and tears it down on exit.

Arguments and piped input are passed straight through to `claude`:

```bash
mclaude --help
echo "Summarize the README" | mclaude -p
```

> **Note:** `mclaude` refuses to start from your home directory (`$HOME`) to prevent accidentally mounting your entire home.

On first run in a project, if `./.claude/settings.json` doesn't exist, `mclaude` creates it
with a sensible default config and prints a notice. An existing config is left untouched.

## Long-running mode

Instead of one container per command, keep a single container running and log into it
to work interactively. Useful when you want a stable, always-ready environment.

**1. Configure.** Copy the example env file and edit it:

```bash
cd mclaude-docker
cp .env.example .env
```

```dotenv
MCLAUDE_WORKDIR=/home/youruser/MyGits   # workspace root, mounted at the same path
CLAUDE_UID=1000                          # id -u
CLAUDE_GID=1000                          # id -g
```

The workspace root is bind-mounted at the **same path** inside the container, so a single
container can serve every project below it.

**2. Make sure the persistent state exists** (created automatically by wrapper mode; do it
manually if you've never run wrapper mode):

```bash
mkdir -p ~/.mclaude/.claude
touch ~/.mclaude/.claude.json
```

**3. Start the container** (builds the image if needed):

```bash
make up           # or: docker compose up -d
```

**4. Log in and work.** Open a shell as the `claude` user and run `claude` inside:

```bash
docker compose exec -u claude mclaude bash
# inside the container — the shell lands in MCLAUDE_WORKDIR:
cd my-project
claude
```

> Inside the long-running container you use `claude` directly — the host `mclaude`
> launcher is only for wrapper mode.

**5. Stop it** when you're done:

```bash
make down         # or: docker compose down
```

The container runs the shared `claude-wrapper` entrypoint with `--keepalive`: it performs
the same UID/GID and Docker-group setup as wrapper mode, then stays alive (`tail -f /dev/null`)
instead of launching `claude`.

## Make targets

| Target         | Description                                              |
|----------------|----------------------------------------------------------|
| `make help`    | List all available targets                               |
| `make docker`  | Build the `mclaude:latest` image                         |
| `make install` | Install the `mclaude` launcher to `/usr/local/bin`       |
| `make shell`   | Drop into a bash shell inside the container (debugging)  |
| `make up`      | Start the long-running container (`docker compose up -d`)|
| `make down`    | Stop and remove the long-running container               |

## Architecture

Three files do the real work:

### `mclaude` – host-side launcher

Installed to `/usr/local/bin`. It:

- refuses to run from `$HOME`,
- seeds a default `./.claude/settings.json` in the current directory if one doesn't exist yet (printing a notice; an existing config is never overwritten),
- bind-mounts `$PWD` at the same path inside the container (`-v $PWD:$PWD`) so absolute paths work correctly,
- passes `CLAUDE_UID`/`CLAUDE_GID` so the container can match host ownership,
- mounts `~/.mclaude/.claude` as a persistent config/state directory,
- forwards the Docker socket (`/var/run/docker.sock`) so Claude can run Docker commands,
- allocates a TTY only when running interactively (piped input works without one).

### `claude-wrapper` – container entrypoint

Copied to `/usr/local/bin` in the image. It:

- adjusts the `claude` user's UID/GID to match `CLAUDE_UID`/`CLAUDE_GID` before any files are touched,
- detects the Docker socket's GID and adds `claude` to that group (Docker-in-Docker without root),
- re-chowns the npm globals after the UID/GID change so `claude update` still works,
- `cd`s into `CLAUDE_WORKDIR` and exec's `claude` as the `claude` user,
- when called with `--keepalive` (long-running mode), does the setup above but then keeps
  the container alive (`tail -f /dev/null`) instead of launching `claude`.

### `docker-compose.yml` – long-running service

Defines the persistent container for long-running mode. It runs `claude-wrapper --keepalive`,
mounts the workspace root (from `.env`) at the same path, wires up the same persistent state
and Docker socket as wrapper mode, and reads `MCLAUDE_WORKDIR`/`CLAUDE_UID`/`CLAUDE_GID` from
`.env`.

### `Dockerfile` – image definition

- Base: `debian:trixie-slim`
- Installs, among others: Node.js, npm, git, ripgrep, fd-find, jq, Docker CLI, openssh-client, vim, python3, g++, make, shellcheck, swaks (with TLS support)
- Installs Claude Code globally via `npm install -g @anthropic-ai/claude-code`
- Gives the `claude` user ownership of the npm globals (self-update without sudo)
- Symlinks `claude` into `~/.local/bin/claude` to satisfy the `/doctor` health check

## State and configuration

| Host path                 | Container path                | Purpose                          |
|---------------------------|-------------------------------|----------------------------------|
| `~/.mclaude/.claude/`     | `/home/claude/.claude/`       | Claude config, memory, sessions  |
| `~/.mclaude/.claude.json` | `/home/claude/.claude.json`   | Claude auth token                |
| `~/.gitconfig`            | `/home/claude/.gitconfig`     | Git identity                     |
| `$PWD`                    | `$PWD` (same path)            | Project files                    |

All Claude state lives under `~/.mclaude/` on the host and therefore persists across container runs.

## Adding dependencies to the image

Add new packages to the first `RUN` block in the `Dockerfile` (before the Docker CLI block), then rebuild with `make docker`.
