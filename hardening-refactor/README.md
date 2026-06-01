# Ollama + Pi Coding Agent — Docker Setup

One container, one command — Ollama serving models with Pi Coding Agent on top.

## Quick Start

```bash
# 1. Build the image
cd image
IMAGE=ollama-pi:latest ./build.sh

# 2. Pull at least one model (on the host)
ollama pull llama3.1:8b

# 3. Launch
./olly
```

## Configuration

All settings are controlled via environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `IMAGE` | `ollama-pi:latest` | Docker image to run |
| `WORKSPACE` | `$(pwd)/workspace` | Host directory mounted at `/workspace` |
| `MEMORY` | `8g` | Container memory limit |
| `CPUS` | `4` | Container CPU limit |
| `PIDS_LIMIT` | `256` | Max processes inside container |
| `NETWORK` | *(default bridge)* | Set to `none` for air-gapped mode |

```bash
# Tight security + air-gapped + 16 GB
WORKSPACE=./safe-dir NETWORK=none MEMORY=16g CPUS=8 ./olly
```

### Inside the container (entrypoint env vars)

| Variable | Default | Purpose |
|----------|---------|---------|
| `OLLAMA_HOST` | `127.0.0.1` | Ollama listen address |
| `OLLAMA_PORT` | `11434` | Ollama listen port |
| `PI_AGENT_DIR` | `/home/piagent/.pi/agent` | Pi config directory |

## Security

This image applies several hardening measures:

- **Non-root user** — Pi agent runs as `piagent`, not root
- **Capability drop** — `--cap-drop=ALL` with only `NET_RAW` added back
- **Resource limits** — Memory, CPU, and pid limits applied by default
- **Workspace isolation** — Uses a dedicated `workspace/` subdirectory, not `$(pwd)` directly
- **Optional air-gap** — Set `NETWORK=none` to disable outbound networking entirely

> **Warning:** Even with these measures, the agent can read/write files in the mounted workspace and (unless air-gapped) make network requests. Treat the workspace accordingly.

## Model Management

The Pi agent ships with `add_model`, `remove_model`, and `list_models` tools. Ollama models are auto-discovered at startup, but you can also manage them at runtime through the agent.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Builds the container image |
| `entrypoint.sh` | Startup script: boot Ollama, discover models, launch Pi |
| `model-manager.ts` | Pi extension for model management tools |
| `olly` | Convenience launcher script |
| `build.sh` | One-command image builder |
