FROM ollama/ollama:latest

RUN apt-get update && apt-get install -y curl ca-certificates gnupg git ripgrep fd-find jq \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_26.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list

RUN apt-get update && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

RUN mkdir -p /home/olly/.ollama /home/olly/.pi/agent/extensions && chown -R 1000:1000 /home/olly

RUN mkdir -p /workspace && chown -R 1000:1000 /workspace

WORKDIR /workspace

ENV HOME=/home/olly

COPY --chown=1000:1000 entrypoint.sh /home/olly/entrypoint.sh
COPY --chown=1000:1000 model-manager.ts /home/olly/.pi/agent/extensions/

RUN chmod +x /home/olly/entrypoint.sh

USER 1000:1000

ENTRYPOINT ["/home/olly/entrypoint.sh"]

