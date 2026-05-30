#!/bin/bash

echo 'Starting Ollama server'

ollama serve > /dev/null 2>&1 &

until curl -s http://127.0.0.1:11434/api/tags | grep -q "models"; do
  echo "Ollama is booting up..."
  sleep 1
done

echo "Ollama is ready. Generating models.json with full model properties..."

mkdir -p /root/.pi/agent

# Generate models.json with proper model properties from Ollama API
cat > /tmp/generate-models.sh << 'SCRIPT'
#!/bin/bash

# Function to get model details from Ollama API
get_model_details() {
    local model_name="$1"
    local response
    
    # Get model info from /api/show
    response=$(curl -s "http://127.0.0.1:11434/api/show" -H "Content-Type: application/json" -d "{\"name\": \"$model_name\"}" 2>/dev/null)
    
    # Extract model info
    echo "$response"
}

# Function to determine context window based on model family/name
get_context_window() {
    local model_name="$1"
    local details="$2"
    
    # Check if model has explicit context length in details
    local context_length=$(echo "$details" | jq -r '.modelinfo.context_length // empty' 2>/dev/null)
    
    if [ -n "$context_length" ] && [ "$context_length" != "null" ]; then
        echo "$context_length"
        return
    fi
    
    # Default context windows based on model patterns
    case "$model_name" in
        *glm*|*GLM*)
            echo "128000"  # GLM models typically support 128K
            ;;
        *qwen*|*Qwen*)
            echo "256000"  # Qwen models often support 256K
            ;;
        *llama-3*|*llama3*)
            echo "128000"
            ;;
        *mistral*|*Mixtral*)
            echo "128000"
            ;;
        *gemma*)
            echo "8192"
            ;;
        *phi-3*|*phi3*)
            echo "128000"
            ;;
        *deepseek*)
            echo "128000"
            ;;
        *)
            echo "128000"  # Safe default
            ;;
    esac
}

# Function to check if model supports thinking/reasoning
supports_thinking() {
    local model_name="$1"
    local details="$2"
    
    # Check for reasoning/thinking capabilities
    local arch=$(echo "$details" | jq -r '.modelinfo.architecture // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]')
    
    # Models known to support thinking/reasoning
    case "$model_name" in
        *o1*|*o3*|*reasoning*|*think*)
            echo "true"
            ;;
        *qwen*|*Qwen*)
            # Qwen models often support thinking
            echo "true"
            ;;
        *glm*|*GLM*)
            # GLM models support reasoning
            echo "true"
            ;;
        *deepseek*)
            echo "true"
            ;;
        *)
            echo "true"  # Default to true for Ollama models
            ;;
    esac
}

# Function to check multimodal support
supports_multimodal() {
    local model_name="$1"
    local details="$2"
    
    # Check for vision/projector in model info
    local has_projector=$(echo "$details" | jq -r '.modelinfo."adapter_type" // empty' 2>/dev/null)
    local has_vision=$(echo "$details" | jq -r '.modelinfo."vision_model" // empty' 2>/dev/null)
    
    # Known multimodal models
    case "$model_name" in
        *llava*|*bakllava*|*moondream*|*vision*|*vl*|*VLM*)
            echo "true"
            ;;
        *qwen*-vl*|*Qwen*-VL*)
            echo "true"
            ;;
        *)
            # Check if model has projector/vision components
            if [ -n "$has_projector" ] || [ -n "$has_vision" ]; then
                echo "true"
            else
                echo "false"
            fi
            ;;
    esac
}

# Start building models.json
echo '{
  "providers": {
    "ollama": {
      "api": "openai-completions",
      "apiKey": "ollama",
      "baseUrl": "http://127.0.0.1:11434/v1",
      "models": ['

# Get list of models
models=$(curl -s http://127.0.0.1:11434/api/tags | jq -r '.models[].name' 2>/dev/null)

first=true
while IFS= read -r model_name; do
    [ -z "$model_name" ] && continue
    
    # Get model details
    details=$(get_model_details "$model_name")
    
    # Get properties
    context_window=$(get_context_window "$model_name" "$details")
    thinking=$(supports_thinking "$model_name" "$details")
    multimodal=$(supports_multimodal "$model_name" "$details")
    
    # Build input capabilities
    if [ "$multimodal" = "true" ]; then
        input_types='["text", "image"]'
    else
        input_types='["text"]'
    fi
    
    # Add comma separator for all but first
    if [ "$first" = true ]; then
        first=false
    else
        echo ","
    fi
    
    # Output model JSON
    cat << MODEL
    {
      "id": "$model_name",
      "input": $input_types,
      "reasoning": $thinking,
      "contextWindow": $context_window
    }
MODEL

done <<< "$models"

echo '
      ]
    }
  }
}'
SCRIPT

chmod +x /tmp/generate-models.sh

# Run the generator
/tmp/generate-models.sh > /root/.pi/agent/models.json

echo "models.json generated successfully:"
cat /root/.pi/agent/models.json

echo ""
echo "Current working directory: $(pwd)"
echo "Checking for AGENTS.md files:"
find . -name "AGENTS.md" -o -name "CLAUDE.md" 2>/dev/null | head -10

echo ""
echo "Launching Pi Harness..."
echo ""
exec ollama launch pi
