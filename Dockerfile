FROM debian:trixie-slim

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
    nodejs \
    npm \
    git \
    curl \
    python3 \
    ripgrep \
    fd-find \
    make \
    jq \
    git \
    openssh-client \
    sudo \
    vim \
    bash \
    make \
    tzdata \
    g++ \
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
RUN npm install -g @anthropic-ai/claude-code

# Let the claude user manage global npm packages (npm install -g, claude update) without sudo
RUN chown -R claude:claude /usr/local/lib/node_modules /usr/local/bin /usr/local/share/man

# Satisfy the claude /doctor check which expects claude at ~/.local/bin/claude
RUN mkdir -p /home/claude/.local/bin && \
    ln -s /usr/local/bin/claude /home/claude/.local/bin/claude && \
    chown -R claude:claude /home/claude/.local

ENV PATH="/usr/local/bin:$PATH"
ENV SHELL=/bin/bash
WORKDIR /src
COPY claude-wrapper /usr/local/bin/
CMD ["/usr/local/bin/claude-wrapper"]

