#!/bin/bash

echo 'Starting Ollama server'

ollama serve > /dev/null 2>&1 &

until curl -s http://127.0.0.1:11434/api/tags | grep -q "models"; do
  echo "Ollama is booting up..."
  sleep 1
done

echo "Ollama is ready. Generating models.json from model metadata..."

mkdir -p /root/.pi/agent

# Write the static header
cat <<"EOF" > /root/.pi/agent/models.json
{
  "providers": {
    "ollama": {
      "api": "openai-completions",
      "apiKey": "ollama",
      "baseUrl": "http://127.0.0.1:11434/v1",
      "models": [
EOF

FIRST=true
for MODEL in $(curl -s http://127.0.0.1:11434/api/tags | jq -r '.models[].name'); do
  # Fetch per-model metadata
  MODEL_INFO=$(curl -s http://127.0.0.1:11434/api/show \
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
    echo "," >> /root/.pi/agent/models.json
  fi

  # Write model entry
  printf '        {\n          "_launch": true,\n          "contextWindow": %s,\n          "id": "%s",\n          "input": %s,\n          "reasoning": %s\n        }' \
    "$CTX" "$MODEL" "$INPUT" "$HAS_REASONING" >> /root/.pi/agent/models.json
done

# Close the JSON
cat <<"EOF" >> /root/.pi/agent/models.json

      ]
    }
  }
}
EOF

echo "Launching Pi Harness"
exec ollama launch pi
