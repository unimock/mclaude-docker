FROM debian:trixie-slim

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
    nodejs \
    npm \
    git \
    curl \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    fd-find \
    jq \
    git \
    openssh-client \
    openssh-server \
    sudo \
    vim \
    bash \
    tzdata \
    g++ \
    shellcheck \
    socat \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
# add more dependencies above if needed
# Add Docker GPG key and repository for Debian
RUN apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker CLI
RUN apt-get update && apt-get install -y docker-ce-cli
# Create user and install pi
RUN useradd -m --shell /bin/bash --home-dir /home/claude claude

# Let claude install packages (apt, pip, ...) without a password prompt.
RUN echo "claude ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/claude && \
    chmod 0440 /etc/sudoers.d/claude
RUN npm install -g @anthropic-ai/claude-code

# Let the claude user manage global npm packages (npm install -g, claude update) without sudo
RUN chown -R claude:claude /usr/local/lib/node_modules /usr/local/bin /usr/local/share/man

# Satisfy the claude /doctor check which expects claude at ~/.local/bin/claude
RUN mkdir -p /home/claude/.local/bin && \
    ln -s /usr/local/bin/claude /home/claude/.local/bin/claude && \
    chown -R claude:claude /home/claude/.local

# Inside the long-running container there is no Docker wrapper to call, but
# muscle memory says `mclaude` — make it an alias for claude.
RUN ln -s /usr/local/bin/claude /usr/local/bin/mclaude

ENV PATH="/usr/local/bin:$PATH"
ENV SHELL=/bin/bash

# Versioning: passed in by `docker compose build` from the VERSION file.
# Declared late so a version bump doesn't bust the cache of the apt layers above.
# Exposed both as an env var (readable inside the container) and as OCI labels
# (readable via `docker inspect` / `mclaude --mclaude-version`).
ARG MCLAUDE_VERSION=dev
ARG BUILD_DATE=unknown
ENV MCLAUDE_VERSION=$MCLAUDE_VERSION
LABEL org.opencontainers.image.title="mclaude" \
      org.opencontainers.image.description="Dockerized Claude Code wrapper" \
      org.opencontainers.image.source="https://github.com/unimock/mclaude-docker" \
      org.opencontainers.image.version="$MCLAUDE_VERSION" \
      org.opencontainers.image.created="$BUILD_DATE"

WORKDIR /src
COPY claude-wrapper /usr/local/bin/
# Self-contained sshd config for long-running mode (pre-shared-key login only).
COPY sshd_config.mclaude /etc/ssh/sshd_config.mclaude
CMD ["/usr/local/bin/claude-wrapper"]

