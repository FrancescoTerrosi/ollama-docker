# How to Use the Docker Environment

## Quick Start

Simply run from your project directory:

```bash
cd /home/francesco/ollamaplayground/AGENTStest
./ollama-docker/olly
```

That's it! Your entire project directory (including `AGENTS.md`) is mounted to `/workspace` in the container.

## Why Your Previous Command Didn't Work

You were running:
```bash
olly "-v ./AGENTS.md:/workspace/AGENTS.md:ro"
```

This approach has issues:

1. **Relative path problem**: `./AGENTS.md` is resolved by Docker from the current shell directory, which may not match what the script expects
2. **Redundant mount**: The script already mounts the entire project directory to `/workspace`
3. **Single file mount**: Mounting just `AGENTS.md` means the model can't read other project files for context

## How It Works Now

The `olly` script does this:

```bash
docker run --rm \
  -v ollama:/root/.ollama \          # Persistent Ollama data
  -v "$PROJECT_DIR:/workspace" \     # Your project files
  $EXTRA_VOLUMES \                    # Optional extra mounts
  -it ollama-docker:latest
```

- **`WORKDIR /workspace`** is set in the Dockerfile
- **`-v "$PROJECT_DIR:/workspace"`** mounts your project (defaults to `pwd`)
- Pi starts in `/workspace` and finds `AGENTS.md` automatically

## Usage Examples

### Basic usage (recommended)
```bash
cd /home/francesco/ollamaplayground/AGENTStest
./ollama-docker/olly
```

### Specify a different project directory
```bash
./ollama-docker/olly "" /path/to/other/project
```

### Add extra volume mounts
```bash
# Use absolute paths for extra volumes
./ollama-docker/olly "-v /some/other/path:/some/other/path:ro"
```

## What Pi Sees Inside the Container

When you run from `/home/francesco/ollamaplayground/AGENTStest`:

```
/workspace/
├── AGENTS.md              # Your "You are Frank" identity
├── ollama-docker/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── olly
└── (other project files)
```

Pi's context loader:
1. Starts at `/workspace` (current directory)
2. Finds `/workspace/AGENTS.md` ✓
3. Also checks `/root/.pi/agent/AGENTS.md` (global, if exists) ✓

## Verifying It Works

When the container starts, you should see:

```
Current working directory: /workspace
Checking for AGENTS.md files:
./AGENTS.md
Launching Pi Harness
```

Then in Pi's startup header, you should see your AGENTS.md loaded.

## Troubleshooting

### AGENTS.md not found?

Check inside the container:
```bash
docker run --rm -v ollama:/root/.ollama -v $(pwd):/workspace ollama-docker:latest ls -la /workspace/AGENTS.md
```

Should show your file.

### Wrong directory mounted?

The script uses `pwd` by default. You can override:
```bash
./ollama-docker/olly "" /absolute/path/to/project
```

### Need to mount additional files?

Use the first argument for extra volumes (use absolute paths):
```bash
./ollama-docker/olly "-v /absolute/path/to/extra:/extra:ro"
```

## Key Points

1. **Don't mount individual files** - mount the whole project directory
2. **Use absolute paths** for any extra volume mounts
3. **Run from your project directory** or specify it as the second argument
4. **Pi finds AGENTS.md automatically** by walking up from the working directory
