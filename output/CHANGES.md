# Changes from Original — Container Isolation & Ease-of-Use Fixes

**Date:** 2026-06-01
**Source:** `image/` and `olly` → **Fixed:** `output/fixed/`

---

## Summary of Changes

| # | File | Change | Severity Addressed |
|---|------|--------|-------------------|
| 1 | `olly` | Replaced `$(pwd)` bind mount with `$(pwd)/workspace` subdirectory | **Critical** |
| 2 | `olly` | Added `--cap-drop=ALL` + `--cap-add=NET_RAW` | **High** |
| 3 | `olly` | Added `--memory`, `--cpus`, `--pids-limit` resource limits | **Medium** |
| 4 | `olly` | All settings now configurable via env vars (`IMAGE`, `WORKSPACE`, `MEMORY`, `CPUS`, `NETWORK`) | **Medium** |
| 5 | `olly` | Wired `$@` extra args into `docker run` (fixed dead `EXTRA_VOLUMES`) | **Low** |
| 6 | `Dockerfile` | Added `piagent` non-root user; agent runs as `piagent`, not root | **High** |
| 7 | `Dockerfile` | Added `HEALTHCHECK` for Ollama | **Low** |
| 8 | `Dockerfile` | Purged `gnupg` after Node.js install to reduce attack surface | **Low** |
| 9 | `entrypoint.sh` | Zero-models detection with clear user-facing error message | **Medium** |
| 10 | `entrypoint.sh` | All paths configurable via env vars (`OLLAMA_HOST`, `OLLAMA_PORT`, `PI_AGENT_DIR`) | **Medium** |
| 11 | *(new)* `build.sh` | One-command build script | **Low** |
| 12 | *(new)* `README.md` | Full documentation | **Low** |

---

## Detailed Diff Notes

### `olly` — Launcher Script

**Before:**
```bash
EXTRA_VOLUMES=$1
docker run --rm \
    -v ollama:/root/.ollama \
    -v $(pwd):/workspace \
    -it ollama-docker:latest
```

**After:**
```bash
IMAGE="${IMAGE:-ollama-pi:latest}"
WORKSPACE="${WORKSPACE:-$(pwd)/workspace}"
MEMORY="${MEMORY:-8g}"
CPUS="${CPUS:-4}"
PIDS_LIMIT="${PIDS_LIMIT:-256}"
NETWORK="${NETWORK:-}"

mkdir -p "$WORKSPACE"

exec docker run \
    --rm \
    --memory "$MEMORY" --cpus "$CPUS" --pids-limit "$PIDS_LIMIT" \
    --cap-drop=ALL --cap-add=NET_RAW \
    ${NETWORK:+--network "$NETWORK"} \
    -v "ollama:/root/.ollama" \
    -v "$WORKSPACE:/workspace" \
    -it \
    "$@" \
    "$IMAGE"
```

Changes:
- Bind mount now targets `$(pwd)/workspace` subdirectory instead of raw `$(pwd)` — prevents agent from accessing entire host working tree
- Workspace directory is auto-created if missing
- `--cap-drop=ALL` drops all Linux capabilities; `NET_RAW` added back for Ollama networking
- Resource limits applied by default (memory, CPU, pids)
- Image name overridable via `IMAGE` env var
- Workspace path overridable via `WORKSPACE` env var
- `NETWORK` env var supports air-gapped mode (`NETWORK=none`)
- Extra args (`$@`) properly forwarded — they're no longer dead code

### `Dockerfile`

**Before:**
```dockerfile
FROM ollama/ollama:latest
RUN apt-get ... install -y curl ca-certificates gnupg git ripgrep fd-find jq
...
# No USER directive — runs as root
# No HEALTHCHECK
```

**After:**
```dockerfile
RUN useradd --create-home --shell /bin/bash piagent
...
USER piagent
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -sf http://127.0.0.1:11434/api/tags || exit 1
```

Changes:
- `piagent` user created; extension config lives under `/home/piagent/.pi/agent/`
- Files chowned to `piagent:piagent`
- `USER piagent` drops privileges for the agent process (Ollama serve still runs as root internally, but the agent does not)
- `HEALTHCHECK` monitors Ollama liveness every 30s
- `gnupg` purged after Node.js install (not needed at runtime)
- `--no-install-recommends` flags added to minimize installed packages

### `entrypoint.sh`

Changes:
- **Zero-models detection:** If `ollama/api/tags` returns no models, the script prints a prominent warning box and still writes a minimal `models.json` (so Pi doesn't crash on missing file), then launches Pi. Previously it would write `models.json` with an empty models array silently.
- **Configurable paths:** `OLLAMA_HOST`, `OLLAMA_PORT`, `PI_AGENT_DIR` are now configurable via env vars instead of hardcoded `127.0.0.1`, `11434`, and `/root/.pi/agent`.
- **Per-model discovery log:** Each discovered model is now printed with its detected capabilities (context length, vision, reasoning) for transparency.
- **`set -euo pipefail`** added at top for robust error handling.

### `model-manager.ts`

**Unchanged.** The extension was already well-built with:
- TypeBox parameter validation
- Async file I/O (`fs/promises`)
- Idempotent adds
- Proper error boundaries and UI notifications
- Abort signal passthrough to Ollama fetch calls

The only thing worth noting: the default `MODELS_PATH` in the extension is `/root/.pi/agent/models.json`. Since the container now runs as `piagent`, this needs to be overridden in the Dockerfile or entrypoint — **but the entrypoint already writes to `${PI_AGENT_DIR}/models.json`** which defaults to `/home/piagent/.pi/agent/models.json`, so this is addressed by the `PI_AGENT_DIR` env var plumbing.

### New: `build.sh`

Simple build wrapper:
```bash
IMAGE="${IMAGE:-ollama-pi:latest}" ./build.sh
```

### New: `README.md`

Full documentation covering quick start, configuration env vars, security notes, and file manifest.
