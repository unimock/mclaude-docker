# mclaude

`mclaude` is a thin Docker wrapper that runs [Claude Code](https://claude.ai/code) inside an isolated Debian container.

It solves two problems:

- **Clean host environment** – Claude Code's dependencies (Node.js, npm, the CLI itself) stay inside the container and never touch the host.
- **Correct file ownership** – all writes into your project happen with the host user's UID/GID, so no root-owned files are left behind.

## Requirements

- Docker (with access to the Docker daemon)
- `make`
- A Claude Code login token (created on first run)

## Installation

```bash
make docker     # Build the mclaude:latest image
make install    # Install the launcher to /usr/local/bin/mclaude (uses sudo)
```

## Usage

After installation, run `mclaude` instead of `claude` from any project directory:

```bash
cd ~/projects/my-project
mclaude
```

Arguments and piped input are passed straight through to `claude`:

```bash
mclaude --help
echo "Summarize the README" | mclaude -p
```

> **Note:** `mclaude` refuses to start from your home directory (`$HOME`) to prevent accidentally mounting your entire home.

## Make targets

| Target         | Description                                              |
|----------------|----------------------------------------------------------|
| `make help`    | List all available targets                               |
| `make docker`  | Build the `mclaude:latest` image                         |
| `make install` | Install the `mclaude` launcher to `/usr/local/bin`       |
| `make shell`   | Drop into a bash shell inside the container (debugging)  |

## Architecture

Three files do the real work:

### `mclaude` – host-side launcher

Installed to `/usr/local/bin`. It:

- refuses to run from `$HOME`,
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
- `cd`s into `CLAUDE_WORKDIR` and exec's `claude` as the `claude` user.

### `Dockerfile` – image definition

- Base: `debian:trixie-slim`
- Installs, among others: Node.js, npm, git, ripgrep, fd-find, jq, Docker CLI, openssh-client, vim, python3, g++, make
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
