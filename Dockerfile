# Long-running mclaude: the unimock/mclaude image (Claude Code, tools, user
# setup) plus an SSH daemon and a keepalive entrypoint.
# Versioning: VERSION is the unimock/mclaude tag to build on (= the bundled
# Claude Code release), passed in by `docker buildx bake`.
ARG MCLAUDE_VERSION=latest
FROM unimock/mclaude:${MCLAUDE_VERSION}

# Build-time only (ARG, not ENV): no interactive apt prompts during the build.
ARG DEBIAN_FRONTEND=noninteractive

# The package generates host keys in /etc/ssh; drop them, ours live in the
# mounted volume (see sshd_config.mclaude).
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    && rm -f /etc/ssh/ssh_host_* \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
# add more dependencies above if needed

# Inside the long-running container there is no Docker launcher to call, but
# muscle memory says `mclaude` — make it an alias for claude.
RUN ln -s /usr/local/bin/claude /usr/local/bin/mclaude

# The ARG before FROM is out of scope here; redeclare it for the labels.
# (ENV MCLAUDE_VERSION comes from the base image.)
ARG MCLAUDE_VERSION
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="mclaude-docker" \
      org.opencontainers.image.description="Long-running mclaude container with sshd" \
      org.opencontainers.image.source="https://github.com/unimock/mclaude-docker" \
      org.opencontainers.image.version="$MCLAUDE_VERSION" \
      org.opencontainers.image.created="$BUILD_DATE"

# Self-contained sshd config (pre-shared-key login only).
COPY sshd_config.mclaude /etc/ssh/sshd_config.mclaude
COPY mclaude-longrunning /usr/local/bin/
CMD ["/usr/local/bin/mclaude-longrunning"]
