#!/bin/bash

echo 'Starting Ollama server'

ollama serve > /dev/null 2>&1 &

until curl -s http://127.0.0.1:11434/api/tags | grep -q "models"; do
  echo "Ollama is booting up..."
  sleep 1
done

echo "Ollama is ready. Generating models.json with model properties..."

mkdir -p /root/.pi/agent

# Generate models.json using jq to properly format the JSON
curl -s http://127.0.0.1:11434/api/tags | jq '
{
  "providers": {
    "ollama": {
      "api": "openai-completions",
      "apiKey": "ollama",
      "baseUrl": "http://127.0.0.1:11434/v1",
      "models": [.models[] | {
        id: .name,
        input: (
          if (.name | test("llava|bakllava|moondream|vision|vl|VLM|qwen.*vl"; "i")) then
            ["text", "image"]
          else
            ["text"]
          end
        ),
        reasoning: (
          if (.name | test("o1|o3|reasoning|think|qwen|glm|deepseek"; "i")) then
            true
          else
            true
          end
        ),
        contextWindow: (
          if (.name | test("glm"; "i")) then 128000
          elif (.name | test("qwen"; "i")) then 256000
          elif (.name | test("llama-3|llama3"; "i")) then 128000
          elif (.name | test("mistral|mixtral"; "i")) then 128000
          elif (.name | test("gemma"; "i")) then 8192
          elif (.name | test("phi-3|phi3"; "i")) then 128000
          elif (.name | test("deepseek"; "i")) then 128000
          else 128000
          end
        )
      }]
    }
  }
}
' > /root/.pi/agent/models.json

echo "models.json generated:"
cat /root/.pi/agent/models.json | jq '.'

echo ""
echo "Current working directory: $(pwd)"
echo "Checking for AGENTS.md files:"
find . -name "AGENTS.md" -o -name "CLAUDE.md" 2>/dev/null | head -10

echo ""
echo "Launching Pi Harness..."
echo ""
exec ollama launch pi
