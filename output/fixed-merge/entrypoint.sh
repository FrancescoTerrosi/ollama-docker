#!/bin/bash
set -euo pipefail

# ── Configurable paths ─────────────────────────────────────────────
# OLLAMA_HOST follows Ollama's own convention and may include the
# port (e.g. "0.0.0.0:11434") — parse it so we always build a valid
# URL. OLLAMA_PORT is honored only when OLLAMA_HOST has no embedded
# port. Instances set OLLAMA_HOST=0.0.0.0:11434, which must not end
# up as "http://0.0.0.0:11434:11434".
RAW_HOST="${OLLAMA_HOST:-127.0.0.1}"
RAW_HOST="${RAW_HOST#*://}"           # strip scheme if present
OLLAMA_BASE="${RAW_HOST%%/*}"         # strip any path
if [[ "$OLLAMA_BASE" == *:* ]] && [[ "${OLLAMA_BASE##*:}" =~ ^[0-9]+$ ]]; then
  OLLAMA_HOSTNAME="${OLLAMA_BASE%:*}"
  OLLAMA_PORT="${OLLAMA_BASE##*:}"
else
  OLLAMA_HOSTNAME="$OLLAMA_BASE"
  OLLAMA_PORT="${OLLAMA_PORT:-11434}"
fi
OLLAMA_URL="http://${OLLAMA_HOSTNAME}:${OLLAMA_PORT}"
PI_AGENT_DIR="${PI_AGENT_DIR:-/home/piagent/.pi/agent}"
MODELS_FILE="${PI_AGENT_DIR}/models.json"

# Make sure `ollama serve` binds the exact host:port we talk to
export OLLAMA_HOST="${OLLAMA_HOSTNAME}:${OLLAMA_PORT}"

echo 'Starting Ollama server...'

ollama serve > /dev/null 2>&1 &

# ── Wait for Ollama to be ready ────────────────────────────────
until curl -s "${OLLAMA_URL}/api/tags" | grep -q "models"; do
  echo "Ollama is booting up..."
  sleep 1
done

echo "Ollama is ready. Discovering models..."

# ── Fetch model list ───────────────────────────────────────────
MODEL_NAMES=$(curl -s "${OLLAMA_URL}/api/tags" | jq -r '.models[].name // empty')

mkdir -p "$PI_AGENT_DIR"

# ── Handle zero models ─────────────────────────────────────────
if [ -z "$MODEL_NAMES" ]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  ⚠  No Ollama models found!                                 ║"
  echo "║                                                            ║"
  echo "║  Pull at least one model before launching. Examples:       ║"
  echo "║    ollama pull llama3.1:8b                                  ║"
  echo "║    ollama pull qwen2.5:7b                                   ║"
  echo "║                                                            ║"
  echo "║  Then restart this container.                              ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  # Write a minimal models.json only if none exists (or it's invalid),
  # so Pi doesn't crash on a missing file — never clobber an existing
  # config that may hold models added at runtime or by other instances.
  if ! jq -e . "$MODELS_FILE" >/dev/null 2>&1; then
    cat > "$MODELS_FILE" <<EOF
{
  "providers": {
    "ollama": {
      "api": "openai-completions",
      "apiKey": "ollama",
      "baseUrl": "${OLLAMA_URL}/v1",
      "models": []
    }
  }
}
EOF
  fi

  echo "Launching Pi Harness (no models available)..."
  exec ollama launch pi
fi

# ── Build discovered model entries ─────────────────────────────
# models.json may already contain models added at runtime (via the
# add_model tool) or written by other instances sharing this volume.
# Merge instead of clobbering: existing entries are kept as-is, and
# only models not already present are appended.
echo "Merging discovered models into $MODELS_FILE..."

TMP_DISCOVERED=$(mktemp)
echo "[" > "$TMP_DISCOVERED"

FIRST=true
while IFS= read -r MODEL; do
  # Fetch per-model metadata
  MODEL_INFO=$(curl -s "${OLLAMA_URL}/api/show" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$MODEL\"}")

  # Extract context length: find namespace-prefixed key (e.g. deepseek4.context_length)
  CTX=$(echo "$MODEL_INFO" | jq -r '[((.model_info // {}) | to_entries[]) | select(.key | endswith(".context_length")) | .value] | max // 128000' 2>/dev/null) || CTX=128000

  # Detect capabilities
  HAS_VISION=$(echo "$MODEL_INFO" | jq -r '(.capabilities | index("vision")) != null' 2>/dev/null) || HAS_VISION=false
  HAS_REASONING=$(echo "$MODEL_INFO" | jq -r '(.capabilities | index("thinking")) != null' 2>/dev/null) || HAS_REASONING=false

  if [ "$HAS_VISION" = "true" ]; then
    INPUT='["text","image"]'
  else
    INPUT='["text"]'
  fi

  # Build the entry with jq so ids are JSON-escaped safely
  ENTRY=$(jq -n \
    --arg id "$MODEL" \
    --argjson ctx "$CTX" \
    --argjson input "$INPUT" \
    --argjson reasoning "$HAS_REASONING" \
    '{_launch: true, contextWindow: $ctx, id: $id, input: $input, reasoning: $reasoning}') || {
      echo "  ⚠ $MODEL: could not parse metadata, skipping"
      continue
    }

  # Add comma separator between entries
  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    echo "," >> "$TMP_DISCOVERED"
  fi
  printf '%s' "$ENTRY" >> "$TMP_DISCOVERED"

  echo "  ✓ $MODEL (ctx=$CTX, vision=$HAS_VISION, reasoning=$HAS_REASONING)"
done <<< "$MODEL_NAMES"
echo "]" >> "$TMP_DISCOVERED"

# ── Merge discovered entries into models.json ──────────────────
if jq -e . "$MODELS_FILE" >/dev/null 2>&1; then
  # Existing valid config: preserve manually added models, other
  # providers, and any custom api/apiKey/baseUrl; append only new ids.
  cp "$MODELS_FILE" "${MODELS_FILE}.bak"
  if jq --slurpfile discovered "$TMP_DISCOVERED" \
        --arg baseUrl "${OLLAMA_URL}/v1" \
        --arg api "openai-completions" --arg apiKey "ollama" '
      (.providers.ollama // {}) as $ep |
      ($ep.models // []) as $em |
      .providers.ollama = ($ep + {
        api: ($ep.api // $api),
        apiKey: ($ep.apiKey // $apiKey),
        baseUrl: ($ep.baseUrl // $baseUrl),
        models: ($em + ($discovered[0] | map(select(.id as $id | ($em | any(.id == $id)) | not))))
      })
    ' "$MODELS_FILE" > "${MODELS_FILE}.new" 2>/dev/null; then
    mv "${MODELS_FILE}.new" "$MODELS_FILE"
  else
    echo "⚠ Merge failed — keeping existing models.json" >&2
  fi
  rm -f "${MODELS_FILE}.new" "${MODELS_FILE}.bak"
else
  # No valid existing config — generate a fresh one.
  jq -n --slurpfile discovered "$TMP_DISCOVERED" \
     --arg baseUrl "${OLLAMA_URL}/v1" \
     '{providers: {ollama: {api: "openai-completions", apiKey: "ollama", baseUrl: $baseUrl, models: $discovered[0]}}}' \
     > "$MODELS_FILE"
fi
rm -f "$TMP_DISCOVERED"

echo ""
echo "Discovered $(echo "$MODEL_NAMES" | wc -l) model(s)."
echo "Launching Pi Harness..."
exec ollama launch pi