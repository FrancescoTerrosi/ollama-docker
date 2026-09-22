# Evaluation Report — Ollama + Pi Coding Agent Docker Setup

**Date:** 2026-06-01
**Scope:** Container isolation and ease-of-use review of the `image/` Docker setup and `olly` launcher
**Evaluator:** Agent-assisted review

---

## Executive Summary

The project packages Pi Coding Agent inside an Ollama Docker container with automatic model discovery and runtime model management. The core idea is strong — one container, one command, and everything works. However, the current implementation has **critical gaps in container isolation** (bind-mounted host filesystem, full network access, root execution) and several **ease-of-use rough edges** (hardcoded paths, no resource limits, fragile entrypoint). It is functional as a development tool but **not safe for production or multi-tenant use** without hardening.

---

## 1. Container Isolation Analysis

### 1.1 Host Filesystem Exposure — CRITICAL

**File:** `olly` (lines 5-7)

```bash
docker run --rm \
    -v ollama:/root/.ollama \
    -v $(pwd):/workspace \
    ...
```

The bind mount `-v $(pwd):/workspace` gives the container **full read/write access** to the host's current working directory. Since the Pi agent can execute arbitrary shell commands, create files, and modify code, this means:

- The agent can **read, modify, or delete any file** in the host's `$(pwd)` tree
- If the user launches `olly` from `$HOME`, the agent can access **all personal files**
- The `--rm` flag prevents dangling containers but doesn't protect host files from within-session modification

**Recommendation:** Narrow the mount to a dedicated, project-scoped subdirectory. Consider a named volume for workspaces or a read-only mount with a separate writable output area.

### 1.2 Network Exposure — HIGH

The container is launched with **default Docker networking** — no network restrictions are applied. This means the container can:

- Make outbound network requests anywhere
- Access other containers on the same Docker network
- Potentially reach host services via the default bridge

Since Pi agents can fetch URLs, search the web, and execute arbitrary code, an unrestricted network is a broad attack surface.

**Recommendation:** Add `--network none` for air-gapped mode, or use `--network isolated-bridge` with egress filtering. At minimum, document the network exposure.

### 1.3 Root Execution — HIGH

**File:** `image/Dockerfile`

```dockerfile
FROM ollama/ollama:latest
```

The `ollama/ollama` base image runs as `root`, and no `USER` directive switches to a non-root user. The entrypoint and all Pi processes run with uid 0 inside the container. While Docker's user namespace can mitigate this, the project doesn't configure it.

**Recommendation:** Add a `USER` directive in the Dockerfile to drop to a non-root user after installing packages, or use `--userns=remap` at runtime.

### 1.4 No Resource Limits — MEDIUM

The `olly` script applies no `--memory`, `--cpus`, `--pids-limit`, or `--ulimit` flags. An Ollama model + Pi agent can consume significant CPU and memory, potentially starving the host.

**Recommendation:** Add sensible resource limits. Example: `--memory=8g --cpus=4 --pids-limit=256`.

### 1.5 No Security Profiles — MEDIUM

No `--security-opt seccomp=...`, `--security-opt apparmor=...`, or `--cap-drop=ALL` flags are set. The container runs with the default Docker seccomp profile, which is permissive.

**Recommendation:** Drop all capabilities (`--cap-drop=ALL`) and add back only what's needed (e.g., `--cap-add=NET_RAW` if networking is kept).

### 1.6 Large Attack Surface in Image — LOW

**File:** `image/Dockerfile` (line 3-4)

```dockerfile
RUN apt-get update && apt-get install -y curl ca-certificates gnupg git ripgrep fd-find jq
```

Installed packages include `git`, `ripgrep`, `fd-find`, `jq`, `curl`, and `gpg`. Each adds binaries that could be exploited if a vulnerability is found.

**Recommendation:** Consider a multi-stage build to separate build-time tools from the runtime image. Remove `gnupg` and unnecessary packages after Node.js installation.

### 1.7 Container Isolation Summary

| Concern | Severity | File(s) |
|---------|----------|---------|
| Bind mount exposes host `$(pwd)` | **Critical** | `olly:5-7` |
| No network restrictions | **High** | `olly` |
| Root execution inside container | **High** | `Dockerfile` |
| No resource limits (CPU/memory) | **Medium** | `olly` |
| No seccomp/AppArmor/capability drops | **Medium** | `olly` |
| Large package install surface | **Low** | `Dockerfile:3-4` |

---

## 2. Ease of Use Analysis

### 2.1 Launch Experience — GOOD

The `olly` script reduces the launch to a single command:

```bash
./olly
```

This is excellent. One script, no flags required, and it Just Works™ (assuming the image is built). The `--rm` flag auto-cleans containers, and named volume (`ollama`) persists models across runs.

### 2.2 Auto-Discovery of Models — GOOD

**File:** `image/entrypoint.sh`

The entrypoint polls `/api/tags`, then queries `/api/show` for each model to extract context length, input modalities, and reasoning capabilities. It then writes a properly formatted `models.json`. This removes the #1 friction point for Ollama users — manual model configuration.

The polling loop (`until curl... | grep "models"`) is a sensible readiness check.

### 2.3 Model Manager Extension — GOOD

**File:** `image/model-manager.ts`

The extension provides three well-designed tools (`add_model`, `remove_model`, `list_models`) with TypeBox validation, async I/O, and proper error handling. Highlights:

- **Idempotent adds** — adding an existing model is a no-op with a clear message
- **Auto-detect** — Ollama capabilities are detected automatically unless explicitly overridden
- **Provider cleanup** — empty providers are deleted on model removal
- **UI notifications** — uses `ctx.ui.notify()` when UI is available
- **Abort signal support** — passes through `signal` to fetch calls

### 2.4 Hardcoded Paths — MEDIUM

**File:** `image/model-manager.ts` (line 9), `image/entrypoint.sh` (multiple lines), `image/Dockerfile`

```typescript
const MODELS_PATH = process.env.MODELS_PATH || "/root/.pi/agent/models.json";
```

While `MODELS_PATH` is environment-overridable, the fallback path `/root/.pi/agent/models.json` is hardcoded. If the base image changes the home directory or the Pi config location changes upstream, this breaks silently.

**File:** `olly` — The Docker image name `ollama-docker:latest` is hardcoded. No way to override via environment variable.

**Recommendation:** Make all paths configurable via environment variables with documented defaults.

### 2.5 No Graceful Handling of Empty Models — MEDIUM

**File:** `image/entrypoint.sh`

If Ollama starts but has **no models downloaded**, the `for` loop never executes. The resulting `models.json` contains an empty `"models": []` array:

```json
{
  "providers": {
    "ollama": {
      "api": "openai-completions",
      "apiKey": "ollama",
      "baseUrl": "http://127.0.0.1:11434/v1",
      "models": []
    }
  }
}
```

Pi may behave unpredictably with an empty models array. No warning is issued to the user.

**Recommendation:** Check for zero models and emit a clear message: "No models found — use `pi pull <model>` or `ollama pull <model>` first."

### 2.6 No Health Check — LOW

**File:** `image/Dockerfile`

No `HEALTHCHECK` instruction is defined. Docker cannot monitor whether Ollama or Pi remain healthy inside the container.

**Recommendation:** Add `HEALTHCHECK --interval=30s CMD curl -f http://127.0.0.1:11434/api/tags || exit 1`

### 2.7 `EXTRA_VOLUMES` Captured but Unused — LOW

**File:** `olly` (line 3)

```bash
EXTRA_VOLUMES=$1
```

The variable is captured from the first CLI argument but never used in the `docker run` command. This is dead code.

**Recommendation:** Either remove it or wire it into the `docker run` args (e.g., `docker run ... $EXTRA_VOLUMES ...`).

### 2.8 Missing Image Build Instructions — LOW

There is no `build.sh` script, no `docker-compose.yml`, and no `README.md` telling users how to build the image. Users must infer:

```bash
cd image && docker build -t ollama-docker:latest .
```

**Recommendation:** Add a simple `build.sh` or include build instructions in a README.

### 2.9 Ease of Use Summary

| Aspect | Rating | Notes |
|--------|--------|-------|
| One-command launch | ✅ Good | `./olly` works |
| Auto model discovery | ✅ Good | Extracts context, vision, reasoning |
| Model management tools | ✅ Good | add/remove/list with auto-detect |
| Hardcoded paths | ⚠️ Medium | MODELS_PATH, image name, home dir |
| Empty models handling | ⚠️ Medium | No warning if Ollama has zero models |
| No health check | 🔵 Low | Docker can't detect failures |
| Dead code (`EXTRA_VOLUMES`) | 🔵 Low | Captured but unused |
| No build/README docs | 🔵 Low | Users must guess build command |

---

## 3. Key Recommendations (Priority-Ordered)

1. **[Critical]** Restrict the workspace bind mount — use a named volume or a dedicated subdirectory instead of `$(pwd)`. Document the exposure if a bind mount is intentional for development.

2. **[High]** Add `--cap-drop=ALL`, resource limits (`--memory`, `--cpus`), and at minimum document the network exposure.

3. **[High]** Switch to a non-root user in the Dockerfile for the Pi agent process.

4. **[Medium]** Handle the zero-models case in `entrypoint.sh` with a clear error message.
   
5. **[Medium]** Make the Docker image name configurable via environment variable in `olly`.

6. **[Low]** Add `HEALTHCHECK`, fix the `EXTRA_VOLUMES` dead code, add `build.sh` and a `README.md`.

---

## 4. What Works Well

- **Automatic model detection pipeline** in `entrypoint.sh` is robust — proper polling, per-model metadata extraction, multiple capability detection strategies.
- **Model manager extension** is well-structured with TypeBox schemas, async I/O, idempotent operations, and proper error boundaries.
- **Persistence model** is sound: named volume for Ollama models, file-based config for Pi — both survive container restarts.
- **Polling readiness check** (`until curl ... grep "models"`) is a reliable pattern for dependency startup.

---

## 5. Appendices

### A. File Manifest

| File | Purpose |
|------|---------|
| `image/Dockerfile` | Builds the Docker image |
| `image/entrypoint.sh` | Container startup: boot Ollama, discover models, launch Pi |
| `image/model-manager.ts` | Pi extension for add/remove/list model tools |
| `olly` | Convenience launcher script |
| `FILAMENT_AGENTS.md` | Unrelated Laravel/Filament auditor agent spec |
| `IMPLEMENTOR_AGENTS.md` | Spec that guided creation of `model-manager.ts` |
| `output/` | Output workspace (audit reports, etc.) |

### B. Quick-Start Suggestions for a README

```bash
# Build
cd image && docker build -t ollama-pi:latest .

# Pull at least one model
ollama pull llama3.1:8b

# Launch
./olly

# Or with resource limits
docker run --rm \
    -v ollama:/root/.ollama \
    -v ./workspace:/workspace \
    --memory=8g --cpus=4 \
    --cap-drop=ALL \
    ollama-pi:latest
```
