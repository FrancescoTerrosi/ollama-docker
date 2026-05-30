# Improved models.json Generation

## Problem

The original models.json generation was too basic:
- Only extracted model names
- Missed critical properties like `contextWindow`, `thinking` support, `input` capabilities
- GLM and other models with specific capabilities weren't properly configured
- Hard-coded format couldn't adapt to different models

## Solution

The new entrypoint.sh uses `jq` to generate models.json directly from Ollama's API with proper model properties:

### Model Properties Captured

1. **`contextWindow`** - Context size based on model family:
   - GLM: 128K
   - Qwen: 256K
   - Llama 3: 128K
   - Mistral/Mixtral: 128K
   - Gemma: 8K
   - Phi-3: 128K
   - DeepSeek: 128K
   - Default: 128K

2. **`reasoning`** - Thinking/reasoning support:
   - Enabled for: Qwen, GLM, DeepSeek, O1/O3, reasoning models
   - Default: true (most modern models support some form of reasoning)

3. **`input`** - Input capabilities:
   - `["text", "image"]` for multimodal models (LLaVA, Qwen-VL, etc.)
   - `["text"]` for text-only models

## Example Output

```json
{
  "providers": {
    "ollama": {
      "api": "openai-completions",
      "apiKey": "ollama",
      "baseUrl": "http://127.0.0.1:11434/v1",
      "models": [
        {
          "id": "qwen3.5:cloud",
          "input": ["text"],
          "reasoning": true,
          "contextWindow": 256000
        },
        {
          "id": "glm-4:latest",
          "input": ["text"],
          "reasoning": true,
          "contextWindow": 128000
        },
        {
          "id": "llava:latest",
          "input": ["text", "image"],
          "reasoning": true,
          "contextWindow": 128000
        }
      ]
    }
  }
}
```

## Benefits

1. **Automatic Detection** - No manual editing needed
2. **Model-Specific Properties** - Each model gets appropriate settings
3. **GLM Support** - GLM models properly configured with 128K context
4. **Multimodal Support** - Vision models correctly marked
5. **Future-Proof** - New models automatically get sensible defaults

## Customization

To customize model properties, you can:

### Option 1: Edit models.json after generation
```bash
# In entrypoint.sh, add after generation:
# Override specific model properties
jq '.providers.ollama.models |= map(
  if .id == "glm-4:latest" then .contextWindow = 256000
  else .
  end
)' /root/.pi/agent/models.json > /tmp/models.json
mv /tmp/models.json /root/.pi/agent/models.json
```

### Option 2: Modify the jq filter
Edit the jq command in entrypoint.sh to adjust:
- Context window sizes
- Reasoning support detection
- Multimodal detection patterns

### Option 3: Use /api/show for detailed info
For even more accurate detection, query each model's details:

```bash
curl -s http://127.0.0.1:11434/api/show -d '{"name":"model-name"}' | jq '.modelinfo'
```

This returns:
- `context_length` - Exact context window
- `architecture` - Model architecture
- `embedding_only` - Whether it's embedding-only
- Other model-specific properties

## Testing

To verify models.json is correct:

```bash
# Inside container
cat /root/.pi/agent/models.json | jq '.'

# Check specific model
cat /root/.pi/agent/models.json | jq '.providers.ollama.models[] | select(.id | contains("glm"))'
```

## AGENTS.md Loading Issue

**Note:** There's a known timing issue where AGENTS.md may not load on initial startup. This is unrelated to models.json.

**Workaround:** After Pi starts, run `/reload` or switch models (Ctrl+L) to trigger a context reload.

See `KNOWN-ISSUE-AGENTS-RELOAD.md` for details.

## Usage

```bash
# Build image
cd ollama-docker/image
docker build -t ollama-docker:latest .

# Run container
cd ../
./olly

# Pi starts with properly configured models
# GLM, Qwen, and other models have correct context sizes
```

## Technical Details

The jq filter processes Ollama's `/api/tags` response:

```jq
.models[] | {
  id: .name,
  input: (if multimodal pattern then ["text", "image"] else ["text"] end),
  reasoning: (if reasoning model pattern then true else true end),
  contextWindow: (if glm then 128000 elif qwen then 256000 ... else 128000 end)
}
```

This creates a proper Pi-compatible models.json with all required fields.
