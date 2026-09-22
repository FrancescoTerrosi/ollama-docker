#!/bin/bash
# Build the Ollama + Pi Docker image
set -euo pipefail

IMAGE="${IMAGE:-ollama-pi:latest}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building image: $IMAGE"
echo "Context:        $SCRIPT_DIR"
echo ""

docker build -t "$IMAGE" "$SCRIPT_DIR"

echo ""
echo "✓ Build complete: $IMAGE"
echo ""
echo "Next steps:"
echo "  1. Pull at least one model:   ollama pull llama3.1:8b"
echo "  2. Launch with:               ./olly"
echo ""
echo "  Or launch directly:"
echo "    docker run --rm -v ollama:/root/.ollama -v ./workspace:/workspace -it $IMAGE"
