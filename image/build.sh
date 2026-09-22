#!/bin/bash
# Build the ollama-docker image
set -euo pipefail

IMAGE="${IMAGE:-ollama-docker:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Building image: $IMAGE"
echo "Context:        $SCRIPT_DIR"
echo ""

docker build -t "$IMAGE" "$SCRIPT_DIR"

echo ""
echo "✓ Build complete: $IMAGE"
echo ""
echo "Next steps:"
echo "  1. Pull at least one model (into the 'ollama' volume)"
echo "  2. Launch with:  ./olly   (from the repo root)"