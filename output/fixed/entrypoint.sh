#!/bin/bash
set -euo pipefail

# ── Configurable paths ─────────────────────────────────────────
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
PI_AGENT_DIR="${PI_AGENT_DIR:-/home/piagent/.pi/agent}"
MODELS_FILE="${PI_AGENT_DIR}/models.json"

echo 'Starting Ollama server...'

ollama serve > /dev/null 2>&1 &

# ── Wait for Ollama to be ready ────────────────────────────────
until curl -s "http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/tags" | grep -q "models"; do
  echo "Ollama is booting up..."
  sleep 1
done

echo "Ollama is ready. Discovering models..."

# ── Fetch model list ───────────────────────────────────────────
MODEL_NAMES=$(curl -s "http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/tags" | jq -r '.models[].name // empty')

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

  # Still write a minimal models.json so Pi doesn't crash on missing file
  mkdir -p "$PI_AGENT_DIR"
  cat > "$MODELS_FILE" <<EOF
{
  "providers": {
    "ollama": {
      "api": "openai-completions",
      "apiKey": "ollama",
      "baseUrl": "http://${OLLAMA_HOST}:${OLLAMA_PORT}/v1",
      "models": []
    }
  }
}
EOF

  echo "Launching Pi Harness (no models available)..."
  exec ollama launch pi
fi

# ── Build models.json from model metadata ──────────────────────
echo "Generating $MODELS_FILE from model metadata..."
mkdir -p "$PI_AGENT_DIR"

# Write the static header
cat > "$MODELS_FILE" <<EOF
{
  "providers": {
    "ollama": {
      "api": "openai-completions",
      "apiKey": "ollama",
      "baseUrl": "http://${OLLAMA_HOST}:${OLLAMA_PORT}/v1",
      "models": [
EOF

FIRST=true
while IFS= read -r MODEL; do
  # Fetch per-model metadata
  MODEL_INFO=$(curl -s "http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/show" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$MODEL\"}")

  # Extract context length: find namespace-prefixed key (e.g. deepseek4.context_length)
  CTX=$(echo "$MODEL_INFO" | jq -r '[.model_info | to_entries[] | select(.key | endswith(".context_length")) | .value] | max // 128000')

  # Detect capabilities
  HAS_VISION=$(echo "$MODEL_INFO" | jq -r '(.capabilities | index("vision")) != null')
  HAS_REASONING=$(echo "$MODEL_INFO" | jq -r '(.capabilities | index("thinking")) != null')

  if [ "$HAS_VISION" = "true" ]; then
    INPUT='["text","image"]'
  else
    INPUT='["text"]'
  fi

  # Add comma separator between entries
  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    echo "," >> "$MODELS_FILE"
  fi

  # Write model entry
  printf '        {\n          "_launch": true,\n          "contextWindow": %s,\n          "id": "%s",\n          "input": %s,\n          "reasoning": %s\n        }' \
    "$CTX" "$MODEL" "$INPUT" "$HAS_REASONING" >> "$MODELS_FILE"

  echo "  ✓ $MODEL (ctx=$CTX, vision=$HAS_VISION, reasoning=$HAS_REASONING)"
done <<< "$MODEL_NAMES"

# Close the JSON
cat >> "$MODELS_FILE" <<"EOF"

      ]
    }
  }
}
EOF

echo ""
echo "Discovered $(echo "$MODEL_NAMES" | wc -l) model(s)."
echo "Launching Pi Harness..."
exec ollama launch pi
