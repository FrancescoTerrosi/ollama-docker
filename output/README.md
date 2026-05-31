# @pi/model-tools

AI-callable tools for dynamically managing the agent's model configuration.

## Structure

```
output/
├── tools.json       OpenAI-compatible tool schemas (for injection into system prompt)
├── handler.mjs      Runtime handler — validates & executes tool calls
├── package.json
└── README.md
```

## How it works

There are **two halves** that must be wired together:

```
User says "add llama3.1"
       │
       ▼
AI model sees tool definitions (from tools.json) ──► decides to call add_model()
       │
       ▼
Agent runtime calls callTool("add_model", {…})    ──► handler.mjs validates & writes models.json
       │
       ▼
Agent reloads / restarts with the new model available
```

### 1. Tool schemas — `tools.json`

OpenAI function-calling format. Inject this into the `tools` field of your chat completion request so the model knows it can call:

| Tool | Purpose | Required params |
|------|---------|-----------------|
| `add_model` | Add a model (creates provider if needed) | `provider`, `id`, `contextWindow` |
| `remove_model` | Remove a model (cleans empty providers) | `provider`, `id` |
| `list_models` | Query current configuration | *(none required)* |

### 2. Runtime handler — `handler.mjs`

```js
import { callTool } from "./handler.mjs";

// Add a model
const result = callTool("add_model", {
  provider: "ollama",
  id: "llama3.1:8b",
  contextWindow: 131072,
  input: ["text"],
  reasoning: false,
  launch: true,
});

// Remove a model
callTool("remove_model", { provider: "ollama", id: "llama3.1:8b" });

// List all models
callTool("list_models", {});

// List a specific provider
callTool("list_models", { provider: "ollama" });
```

### CLI (for testing)

```bash
node handler.mjs add_model '{"provider":"ollama","id":"llama3.1:8b","contextWindow":131072}'
node handler.mjs remove_model '{"provider":"ollama","id":"llama3.1:8b"}'
node handler.mjs list_models
node handler.mjs list_models '{"provider":"ollama"}'
```

## Adding provider-level config

When calling `add_model` for a provider that doesn't exist yet, you can include provider-level fields:

```json
{
  "provider": "openai",
  "id": "gpt-4o",
  "contextWindow": 128000,
  "api": "openai-completions",
  "apiKey": "sk-...",
  "baseUrl": "https://api.openai.com/v1"
}
```

These are **ignored** if the provider already exists.

## Idempotency

- `add_model` is idempotent — calling it twice with the same `provider`+`id` is a no-op.
- `remove_model` returns an error if the model or provider doesn't exist.

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `MODELS_PATH` | `/root/.pi/agent/models.json` | Path to the models config file |

## Integration checklist

- [ ] Import `tools.json` into your agent's tool definitions at inference time
- [ ] Wire `callTool()` into your agent's tool-execution loop
- [ ] Trigger a provider/model reload after `add_model` or `remove_model` calls
- [ ] (Optional) Gate `remove_model` behind a confirmation step to prevent accidental deletes