FROM ollama/ollama:latest

# ── Install system deps ────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git ripgrep fd-find jq \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_26.x nodistro main" \
       | tee /etc/apt/sources.list.d/nodesource.list

RUN apt-get update && apt-get install -y --no-install-recommends nodejs \
    && apt-get purge -y gnupg \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# ── Install Pi Coding Agent ────────────────────────────────────
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# ── Create non-root user for the agent ─────────────────────────
RUN useradd --create-home --shell /bin/bash piagent

# ── Set up extension and entrypoint ────────────────────────────
RUN mkdir -p /home/piagent/.pi/agent/extensions

COPY model-manager.ts /home/piagent/.pi/agent/extensions/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ── Ownership ──────────────────────────────────────────────────
RUN chown -R piagent:piagent /home/piagent/.pi

# ── Health check ───────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -sf http://127.0.0.1:11434/api/tags || exit 1

# ── Runtime ────────────────────────────────────────────────────
WORKDIR /workspace
USER piagent

ENTRYPOINT ["/entrypoint.sh"]
