import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

// ── Config ──────────────────────────────────────────────────────────────────
const MODELS_PATH = process.env.MODELS_PATH || "/root/.pi/agent/models.json";

// ── TypeBox Schemas ─────────────────────────────────────────────────────────

const AddModelParams = Type.Object(
  {
    provider: Type.String({
      description: "Provider name, e.g. 'ollama', 'openai', 'anthropic'",
    }),
    id: Type.String({
      description: "Model ID as the provider knows it, e.g. 'llama3.1:8b'",
    }),
    contextWindow: Type.Optional(
      Type.Integer({
        description:
          "Maximum context window size in tokens (optional — auto-detected for Ollama models)",
      })
    ),
    input: Type.Optional(
      Type.Array(Type.String(), {
        description:
          "Supported input modalities, e.g. ['text', 'image'] (optional — auto-detected for Ollama models)",
      })
    ),
    reasoning: Type.Optional(
      Type.Boolean({
        description:
          "Whether the model supports reasoning/thinking (optional — auto-detected for Ollama models)",
      })
    ),
    launch: Type.Optional(
      Type.Boolean({
        description:
          "Set _launch flag — whether to start the model on agent boot",
      })
    ),
    api: Type.Optional(
      Type.String({
        description:
          "API compatibility type (only used when creating a new provider), e.g. 'openai-completions'",
      })
    ),
    apiKey: Type.Optional(
      Type.String({
        description:
          "API key for the provider (only used when creating a new provider)",
      })
    ),
    baseUrl: Type.Optional(
      Type.String({
        description:
          "Base URL for the provider API (only used when creating a new provider)",
      })
    ),
  },
  {
    additionalProperties: false,
  }
);

const RemoveModelParams = Type.Object(
  {
    provider: Type.String({
      description: "Provider name",
    }),
    id: Type.String({
      description: "Model ID to remove",
    }),
  },
  {
    additionalProperties: false,
  }
);

const ListModelsParams = Type.Object(
  {
    provider: Type.Optional(
      Type.String({
        description:
          "Filter by provider name. Omit to list all providers.",
      })
    ),
  },
  {
    additionalProperties: false,
  }
);

// ── Ollama auto-detection ───────────────────────────────────────────────────

/**
 * Pull a model from Ollama.
 * Strips /v1 from the baseUrl since /api/pull is a native Ollama endpoint.
 */
async function pullOllamaModel(
  modelName: string,
  baseUrl = "http://127.0.0.1:11434/v1",
  signal?: AbortSignal
): Promise<void> {
  const origin = baseUrl.replace(/\/v1\/?$/, "");
  const resp = await fetch(`${origin}/api/pull`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name: modelName }),
    signal,
  });
  if (!resp.ok) {
    throw new Error(
      `Ollama /api/pull returned ${resp.status} for "${modelName}"`
    );
  }
}

/**
 * Fetch model metadata from the Ollama /api/show endpoint.
 * Strips /v1 from the baseUrl since /api/show is a native Ollama endpoint.
 */
async function fetchOllamaModelInfo(
  modelName: string,
  baseUrl = "http://127.0.0.1:11434/v1",
  signal?: AbortSignal
) {
  const origin = baseUrl.replace(/\/v1\/?$/, "");
  const resp = await fetch(`${origin}/api/show`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name: modelName }),
    signal,
  });
  if (!resp.ok) {
    throw new Error(
      `Ollama /api/show returned ${resp.status} for "${modelName}"`
    );
  }
  return resp.json();
}

/** Parse context window from model parameters (looks for num_ctx in parameters, then model_info). */
function parseContextWindow(modelInfo: any): number {
  const params = modelInfo.parameters || "";
  const m = params.match(/num_ctx\s+(\d+)/i);
  if (m) return parseInt(m[1], 10);

  // Fallback: check model_info for any *context_length field
  const modelInfoObj = modelInfo.model_info || {};
  for (const [key, value] of Object.entries(modelInfoObj)) {
    if (key.endsWith("context_length") && typeof value === "number") {
      return value;
    }
  }

  // Final fallback: sensible default for modern models
  return 128000;
}

/** Detect whether the model supports image input. */
function detectInputModalities(modelInfo: any): string[] {
  const modelfile = (modelInfo.modelfile || "").toLowerCase();
  const details = modelInfo.details || {};
  const family = (details.family || "").toLowerCase();

  // Known multimodal model families / patterns
  const multimodalSignatures = [
    "qwen",
    "qwen2",
    "qwen2.5",
    "qwen3",
    "llava",
    "bakllava",
    "moondream",
    "minicpm-v",
    "minicpmv",
    "cogvlm",
    "fuyu",
    "phi3-v",
    "phi-3-vision",
    "llama3.2-vision",
    "gemma3",
    "gemma-3",
  ];

  const multimodal =
    multimodalSignatures.some((s) => family.includes(s)) ||
    modelfile.includes("clip") ||
    modelfile.includes("vision");

  return multimodal ? ["text", "image"] : ["text"];
}

/** Detect whether the model supports reasoning / extended thinking. */
function detectReasoning(modelInfo: any): boolean {
  const details = modelInfo.details || {};
  const family = (details.family || "").toLowerCase();
  const template = (modelInfo.template || "").toLowerCase();
  const capabilities = modelInfo.capabilities || [];

  // Models that commonly support reasoning / chain-of-thought
  const reasoningFamilies = [
    "qwen",
    "qwen2",
    "qwen2.5",
    "qwen3",
    "deepseek",
    "deepseek-v",
    "deepseek-r",
    "glm",
    "chatglm",
  ];

  return (
    capabilities.includes("thinking") ||
    reasoningFamilies.some((f) => family.includes(f)) ||
    template.includes("think") ||
    template.includes("thinking") ||
    template.includes("reasoning")
  );
}

/**
 * Auto-detect model capabilities from Ollama when the provider is 'ollama'
 * and the user hasn't explicitly provided them.
 */
async function autoDetectCapabilities(
  providerName: string,
  id: string,
  args: any,
  providerConfig?: { baseUrl?: string }
) {
  if (providerName !== "ollama") return null;

  // Only auto-detect fields that were NOT explicitly given
  const needsDetection = [
    "contextWindow",
    "input",
    "reasoning",
  ].some((k) => !(k in args));

  if (!needsDetection) return null;

  const baseUrl = providerConfig?.baseUrl || "http://127.0.0.1:11434/v1";
  const info = await fetchOllamaModelInfo(id, baseUrl);

  const detected: any = {};
  if (!("contextWindow" in args))
    detected.contextWindow = parseContextWindow(info);
  if (!("input" in args)) detected.input = detectInputModalities(info);
  if (!("reasoning" in args)) detected.reasoning = detectReasoning(info);

  return detected;
}

// ── Helpers ─────────────────────────────────────────────────────────────────

interface ModelConfig {
  providers: Record<string, ProviderConfig>;
}

interface ProviderConfig {
  api?: string;
  apiKey?: string;
  baseUrl?: string;
  models: ModelEntry[];
}

interface ModelEntry {
  id: string;
  contextWindow?: number;
  input?: string[];
  reasoning?: boolean;
  _launch?: boolean;
}

async function loadConfig(): Promise<ModelConfig> {
  const content = await readFile(MODELS_PATH, "utf-8");
  const config = JSON.parse(content);
  config.providers = config.providers || {};
  return config;
}

async function saveConfig(config: ModelConfig): Promise<void> {
  await writeFile(
    MODELS_PATH,
    JSON.stringify(config, null, 2) + "\n",
    "utf-8"
  );
}

function findModel(
  provider: ProviderConfig,
  id: string
): ModelEntry | undefined {
  if (!provider.models) return undefined;
  return provider.models.find((m) => m.id === id);
}

// ── Extension Entry Point ───────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  // Register add_model tool
  pi.registerTool({
    name: "add_model",
    label: "Add Model",
    description:
      "Add a new model to a provider in the agent configuration. Creates the provider if it doesn't exist.",
    parameters: AddModelParams,
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const {
        provider: providerName,
        id,
        contextWindow,
        input,
        reasoning,
        launch = false,
        api = "openai-completions",
        apiKey = "",
        baseUrl = "",
      } = params;

      try {
        const config = await loadConfig();

        // Ensure the provider exists (or grab its config if it already does)
        const existingProvider = config.providers[providerName];
        if (!existingProvider) {
          config.providers[providerName] = {
            api,
            ...(apiKey ? { apiKey } : {}),
            ...(baseUrl ? { baseUrl } : {}),
            models: [],
          };
        }

        const provider = config.providers[providerName];

        // Bail out if model already exists (idempotent)
        if (findModel(provider, id)) {
          const message = `Model "${id}" already exists under "${providerName}" — no changes made.`;
          if (ctx.hasUI) {
            ctx.ui.notify(message, "info");
          }
          return {
            content: [{ type: "text", text: message }],
            details: { provider: providerName, id, unchanged: true },
          };
        }

        // Auto-detect capabilities from Ollama if not explicitly given
        // First, pull the model to ensure it's available
        if (providerName === "ollama") {
          try {
            const pullBaseUrl = existingProvider?.baseUrl || baseUrl || "http://127.0.0.1:11434/v1";
            await pullOllamaModel(id, pullBaseUrl, signal);
          } catch (pullErr) {
            // If pull fails, continue anyway - model might already be available
            // or could be a cloud model that doesn't need pulling
          }
        }

        const detected = await autoDetectCapabilities(
          providerName,
          id,
          params,
          existingProvider || { api, apiKey, baseUrl }
        );

        const finalContextWindow =
          contextWindow ?? detected?.contextWindow ?? 128000;
        const finalInput = input ?? detected?.input ?? ["text"];
        const finalReasoning = reasoning ?? detected?.reasoning ?? false;

        const entry: ModelEntry = {
          ...(launch ? { _launch: true } : {}),
          contextWindow: finalContextWindow,
          id,
          input: finalInput,
          reasoning: finalReasoning,
        };

        provider.models.push(entry);
        await saveConfig(config);

        const autoTags = detected ? " (auto-detected)" : "";
        const message = `Added model "${id}" to provider "${providerName}"${autoTags}.`;

        if (ctx.hasUI) {
          ctx.ui.notify(message, "success");
        }

        return {
          content: [{ type: "text", text: message }],
          details: {
            provider: providerName,
            id,
            contextWindow: finalContextWindow,
            input: finalInput,
            reasoning: finalReasoning,
            autoDetected: !!detected,
          },
        };
      } catch (err) {
        const errorMessage = `Failed to add model: ${err.message}`;
        if (ctx.hasUI) {
          ctx.ui.notify(errorMessage, "error");
        }
        return {
          content: [{ type: "text", text: errorMessage }],
          details: { error: err.message },
        };
      }
    },
  });

  // Register remove_model tool
  pi.registerTool({
    name: "remove_model",
    label: "Remove Model",
    description:
      "Remove a model from a provider. Removes the provider entirely if it has no remaining models.",
    parameters: RemoveModelParams,
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const { provider: providerName, id } = params;

      try {
        const config = await loadConfig();

        if (!config.providers[providerName]) {
          const message = `Provider "${providerName}" not found.`;
          if (ctx.hasUI) {
            ctx.ui.notify(message, "error");
          }
          return {
            content: [{ type: "text", text: message }],
            details: { error: message },
          };
        }

        const provider = config.providers[providerName];
        const idx = provider.models?.findIndex((m) => m.id === id);

        if (idx === undefined || idx === -1) {
          const message = `Model "${id}" not found under "${providerName}".`;
          if (ctx.hasUI) {
            ctx.ui.notify(message, "error");
          }
          return {
            content: [{ type: "text", text: message }],
            details: { error: message },
          };
        }

        provider.models.splice(idx, 1);

        // Clean up empty provider
        if (provider.models.length === 0) {
          delete config.providers[providerName];
        }

        await saveConfig(config);

        const message = `Removed model "${id}" from provider "${providerName}".`;

        if (ctx.hasUI) {
          ctx.ui.notify(message, "success");
        }

        return {
          content: [{ type: "text", text: message }],
          details: { provider: providerName, id, removed: true },
        };
      } catch (err) {
        const errorMessage = `Failed to remove model: ${err.message}`;
        if (ctx.hasUI) {
          ctx.ui.notify(errorMessage, "error");
        }
        return {
          content: [{ type: "text", text: errorMessage }],
          details: { error: err.message },
        };
      }
    },
  });

  // Register list_models tool
  pi.registerTool({
    name: "list_models",
    label: "List Models",
    description:
      "List all configured models, optionally filtered by provider.",
    parameters: ListModelsParams,
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const { provider: providerName } = params || {};

      try {
        const config = await loadConfig();

        if (providerName) {
          if (!config.providers[providerName]) {
            const message = `Provider "${providerName}" not found.`;
            if (ctx.hasUI) {
              ctx.ui.notify(message, "error");
            }
            return {
              content: [{ type: "text", text: message }],
              details: { error: message },
            };
          }
          const provider = config.providers[providerName];
          const resultText = `Provider "${providerName}" has ${provider.models.length} model(s): ${provider.models.map((m) => m.id).join(", ")}`;
          return {
            content: [{ type: "text", text: resultText }],
            details: { provider: providerName, ...provider },
          };
        }

        const providerList = Object.keys(config.providers).join(", ");
        const resultText = `Configured providers: ${providerList || "none"}`;
        return {
          content: [{ type: "text", text: resultText }],
          details: { providers: config.providers },
        };
      } catch (err) {
        const errorMessage = `Failed to list models: ${err.message}`;
        if (ctx.hasUI) {
          ctx.ui.notify(errorMessage, "error");
        }
        return {
          content: [{ type: "text", text: errorMessage }],
          details: { error: err.message },
        };
      }
    },
  });
}
