# Ollama + Pi Coding Agent — Docker Setup

One container, one command — Ollama serving local models with the Pi Coding Agent on top.

## Quick Start

```bash
# 1. Build the image
cd image && ./build.sh

# 2. Pull at least one model into the 'ollama' volume, e.g.:
docker run --rm -v ollama:/root/.ollama ollama/ollama:latest pull llama3.1:8b

# 3. Launch (from the repo root)
./olly
```

The entrypoint auto-discovers every model in the volume at startup and registers it in Pi's `models.json`.

## Configuration

All launcher settings are controlled via environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `IMAGE` | `ollama-docker:latest` | Docker image to run |
| `WORKSPACE` | `$(pwd)/workspace` | Host directory mounted at `/workspace` |
| `MEMORY` | `8g` | Container memory limit |
| `CPUS` | `4` | Container CPU limit |
| `PIDS_LIMIT` | `256` | Max processes inside container |
| `NETWORK` | *(default bridge)* | Set to `none` for air-gapped mode |

```bash
# Tight security + air-gapped + 16 GB
WORKSPACE=./safe-dir NETWORK=none MEMORY=16g CPUS=8 ./olly
```

Extra flags given on the command line are passed straight to `docker run`:

```bash
./olly --network none
```

### Inside the container (entrypoint env vars)

| Variable | Default | Purpose |
|----------|---------|---------|
| `OLLAMA_HOST` | `127.0.0.1` | Ollama listen address (may include `:port`) |
| `OLLAMA_PORT` | `11434` | Ollama listen port (used only if `OLLAMA_HOST` has no port) |
| `PI_AGENT_DIR` | `/home/olly/.pi/agent` | Pi config directory |

## Security

This image applies several hardening measures:

- **Non-root user** — everything runs as uid 1000 (`HOME=/home/olly`)
- **Capability drop** — `--cap-drop=ALL` with only `NET_RAW` added back
- **Resource limits** — Memory, CPU, and pid limits applied by default
- **Workspace isolation** — Mounts a dedicated `workspace/` subdirectory, not `$(pwd)` directly
- **Optional air-gap** — Set `NETWORK=none` to disable networking entirely

State lives in two named volumes: `ollama` (models) and `pi` (agent config, including `models.json`).

> **Warning:** Even with these measures, the agent can read/write files in the mounted workspace and (unless air-gapped) make network requests. Treat the workspace accordingly.

## Model Management

The Pi agent ships with `add_model`, `remove_model`, and `list_models` tools. Models are auto-discovered and merged into `models.json` at startup — existing entries (including models added at runtime) are never clobbered. The extension resolves the config path the same way pi itself does (`MODELS_PATH` override, then the agent dir), so it works for any user the agent runs as.

## Files

| File | Purpose |
|------|---------|
| `image/Dockerfile` | Builds the container image |
| `image/entrypoint.sh` | Startup script: boot Ollama, discover models, launch Pi |
| `image/model-manager.ts` | Pi extension for model management tools |
| `image/build.sh` | One-command image builder |
| `olly` | Convenience launcher script (repo root) |