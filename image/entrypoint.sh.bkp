#!/bin/bash

echo 'Starting Ollama server'

ollama serve > /dev/null 2>&1 &

until curl -s http://127.0.0.1:11434/api/tags | grep -q "models"; do
  echo "Ollama is booting up..."
  sleep 1
done

echo "Ollama is ready. Safely generating models.json via file streams..."

mkdir -p /root/.pi/agent

cat <<"EOF" > /root/.pi/agent/models.json
{
  "providers": {
    "ollama": {
      "api": "openai-completions",
      "apiKey": "ollama",
      "baseUrl": "http://127.0.0.1:11434/v1",
      "models": [
EOF

curl -s http://127.0.0.1:11434/api/tags | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="name" && $(i+2) != "name") print "{\"id\":\""$(i+2)"\",\"input\":[\"text\",\"image\"],\"reasoning\":true}"}' | xargs -d '\n' | sed 's/ /,/g' >> /root/.pi/agent/models.json

cat <<"EOF" >> /root/.pi/agent/models.json
      ]
    }
  }
}
EOF

echo "Launching Pi Harness"
exec ollama launch pi
