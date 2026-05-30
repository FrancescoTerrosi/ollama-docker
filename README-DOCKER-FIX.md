# Docker Ollama + Pi Setup - AGENTS.md Fix

## The Problem

Pi loads `AGENTS.md` files by walking up from the **current working directory**. In the Docker environment:

- Container's working directory was `/workspace`
- Project files with `AGENTS.md` weren't properly mounted
- Pi couldn't find context files because it searches relative to `cwd`

## The Solution

### Changes Made

1. **Updated `olly` script** to:
   - Mount your project directory to `/workspace` in the container
   - Set the working directory (`-w /workspace`) so Pi starts in the right place
   - Accept an optional second argument for the project path (defaults to current directory)

2. **Updated `entrypoint.sh`** to:
   - Display the current working directory at startup
   - List any `AGENTS.md` or `CLAUDE.md` files found
   - This helps debug if files are being mounted correctly

### Usage

```bash
# From your project directory with AGENTS.md
cd /home/francesco/ollamaplayground/AGENTStest
./ollama-docker/olly

# Or specify a different project directory
./ollama-docker/olly "" /path/to/your/project

# Or with extra volumes (first argument)
./ollama-docker/olly "-v /some/other/path:/some/other/path" /path/to/your/project
```

### How It Works

The updated `olly` script now runs:

```bash
docker run --rm \
  -v ollama:/root/.ollama \
  -v "$PROJECT_DIR:/workspace" \
  -w /workspace \
  -it ollama-docker:latest
```

This ensures:
- Your project directory (with `AGENTS.md`) is mounted at `/workspace`
- The container starts in `/workspace` (where Pi can find your context files)
- Pi walks up from `/workspace` and finds your `AGENTS.md`

### Verifying It Works

When you start the container, you should see output like:

```
Current working directory: /workspace
Checking for AGENTS.md files:
./AGENTS.md
Launching Pi Harness
```

And in Pi's startup header, you should see your `AGENTS.md` content loaded.

## Testing

From `/home/francesco/ollamaplayground/AGENTStest`:

```bash
cd /home/francesco/ollamaplayground/AGENTStest
./ollama-docker/olly
```

Pi should now load both:
1. The global `AGENTS.md` from `/root/.pi/agent/` (if exists)
2. Your project's `AGENTS.md` from `/workspace/AGENTS.md`

## Troubleshooting

If AGENTS.md still doesn't load:

1. **Check the mount**: Inside the container, run `ls -la /workspace`
2. **Check permissions**: Ensure the file is readable
3. **Check working directory**: Run `pwd` inside the container before launching pi
4. **Verify file name**: Must be exactly `AGENTS.md` (case matters in Linux)

## Alternative: Global AGENTS.md

If you want a global AGENTS.md for all projects, you can also create one in the container:

```bash
# Add to Dockerfile or run manually
cat > /root/.pi/agent/AGENTS.md << 'EOF'
Your global instructions here
EOF
```

This will always be loaded regardless of the working directory.
