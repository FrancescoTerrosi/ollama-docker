# Docker AGENTS.md Loading Issue - Known Quirk

## The Issue

When starting the Docker container, AGENTS.md may not load initially. However, **switching models** or running `/reload` fixes it immediately.

This is a **timing issue**, not a mount issue.

## Why It Happens

Pi loads context files (AGENTS.md) **once at startup**. There's a race condition where:

1. Pi starts and calls `loadProjectContextFiles()`
2. At that exact moment, the volume mount state isn't fully settled
3. Pi caches "no AGENTS.md found"
4. When you switch models → `session.reload()` → re-reads disk → finds files ✓

## The Fix (Simple)

After Pi starts, just do one of these:

### Option 1: Switch models (recommended)
```
Ctrl+L  # Open model selector
Enter   # Select your model (even if it's the same one)
```

### Option 2: Run reload command
```
/reload  # In Pi's editor
```

### Option 3: Cycle models
```
Ctrl+P  # Cycle to next model
Ctrl+P  # Cycle back if needed
```

## Why Model Switching Works

When you switch models, Pi's `setModel()` function calls:
1. `session.reload()` 
2. `this._resourceLoader.reload()`
3. Which re-reads AGENTS.md from disk
4. Files are found and loaded correctly ✓

## Volume Mount IS Working

The fact that model switching fixes it proves the volume mount is working correctly:

```bash
# Inside container after startup
$ pwd
/workspace

$ ls -la AGENTS.md
-rw-rw-r-- 1 francesco francesco 28 May 30 13:23 AGENTS.md

$ cat AGENTS.md
# IDENTITY
You are Frank.
```

The file is there - it just needs a reload to be picked up.

## Future Fix

This could be fixed in Pi by:
- Adding a small delay before loading context files
- Or watching for mount state changes
- Or reloading context files after a brief startup delay

For now, just run `/reload` or switch models after startup.

## Usage

```bash
# Start container
cd /home/francesco/ollamaplayground/AGENTStest
./ollama-docker/olly

# Pi starts...

# If AGENTS.md not loaded (check startup header):
# Option A: Press Ctrl+L, then Enter (switch models)
# Option B: Type /reload in editor

# Now AGENTS.md is loaded!
```

## Verification

After switching models or running /reload, check Pi's startup header - it should show:

```
Context: AGENTS.md (2 lines)
```

Or ask Pi:
```
"Who are you?"
```

It should respond based on your AGENTS.md content (e.g., "I am Frank, a Code Auditor...")
