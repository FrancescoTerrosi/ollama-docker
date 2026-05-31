#!/usr/bin/env node

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

// ── Config ──────────────────────────────────────────────────────────────────
const MODELS_PATH = process.env.MODELS_PATH || "/root/.pi/agent/models.json";

// ── Helpers ─────────────────────────────────────────────────────────────────
function loadConfig() {
  return JSON.parse(readFileSync(MODELS_PATH, "utf-8"));
}

function saveConfig(config) {
  writeFileSync(MODELS_PATH, JSON.stringify(config, null, 2) + "\n");
}

function findModel(provider, id) {
  if (!provider.models) return undefined;
  return provider.models.find((m) => m.id === id);
}

// ── Handlers ────────────────────────────────────────────────────────────────

/**
 * add_model — insert a new model (and optionally a new provider) into config.
 * Falls through silently if the model already exists (idempotent).
 */
function addModel(args) {
  const {
    provider: providerName,
    id,
    contextWindow,
    input = ["text"],
    reasoning = false,
    launch = false,
    // provider-level — only used when creating a new provider
    api = "openai-completions",
    apiKey = "",
    baseUrl = "",
  } = args;

  const config = loadConfig();

  // Ensure the provider exists
  if (!config.providers[providerName]) {
    config.providers[providerName] = {
      api,
      ...(apiKey ? { apiKey } : {}),
      ...(baseUrl ? { baseUrl } : {}),
      models: [],
    };
  }

  const provider = config.providers[providerName];

  // Bail out if model already exists
  if (findModel(provider, id)) {
    return { ok: true, message: `Model "${id}" already exists under "${providerName}" — no changes made.` };
  }

  const entry = {
    ...(launch ? { _launch: true } : {}),
    contextWindow,
    id,
    input,
    reasoning,
  };

  provider.models.push(entry);
  saveConfig(config);

  return { ok: true, message: `Added model "${id}" to provider "${providerName}".` };
}

/**
 * remove_model — delete a model. Removes the provider if it becomes empty.
 */
function removeModel(args) {
  const { provider: providerName, id } = args;

  const config = loadConfig();

  if (!config.providers[providerName]) {
    return { ok: false, message: `Provider "${providerName}" not found.` };
  }

  const provider = config.providers[providerName];
  const idx = provider.models?.findIndex((m) => m.id === id);

  if (idx === undefined || idx === -1) {
    return { ok: false, message: `Model "${id}" not found under "${providerName}".` };
  }

  provider.models.splice(idx, 1);

  // Clean up empty provider
  if (provider.models.length === 0) {
    delete config.providers[providerName];
  }

  saveConfig(config);

  return { ok: true, message: `Removed model "${id}" from provider "${providerName}".` };
}

/**
 * list_models — return current configuration of models.
 */
function listModels(args) {
  const { provider: providerName } = args || {};
  const config = loadConfig();

  if (providerName) {
    if (!config.providers[providerName]) {
      return { ok: false, message: `Provider "${providerName}" not found.` };
    }
    return {
      ok: true,
      provider: providerName,
      ...config.providers[providerName],
    };
  }

  return { ok: true, providers: config.providers };
}

// ── Router ──────────────────────────────────────────────────────────────────
const HANDLERS = {
  add_model: addModel,
  remove_model: removeModel,
  list_models: listModels,
};

/**
 * Call a tool by name with the given arguments.
 * Returns the tool result as a plain object.
 *
 * @param {string} toolName — one of "add_model", "remove_model", "list_models"
 * @param {object} args    — arguments matching the tool's parameter schema
 * @returns {{ ok: boolean, message?: string, … }}
 */
export function callTool(toolName, args) {
  const handler = HANDLERS[toolName];
  if (!handler) {
    return { ok: false, message: `Unknown tool: "${toolName}". Available: ${Object.keys(HANDLERS).join(", ")}` };
  }

  try {
    return handler(args);
  } catch (err) {
    return { ok: false, message: `Tool error: ${err.message}` };
  }
}

// ── CLI ─────────────────────────────────────────────────────────────────────
// Allows running: node handler.mjs <tool_name> '<json_args>'
if (process.argv[1] && process.argv[1].endsWith("handler.mjs")) {
  const [, , toolName, argsJson] = process.argv;

  if (!toolName) {
    console.error("Usage: node handler.mjs <tool_name> [json_args]");
    console.error("Tools:", Object.keys(HANDLERS).join(", "));
    process.exit(1);
  }

  const args = argsJson ? JSON.parse(argsJson) : {};
  const result = callTool(toolName, args);
  console.log(JSON.stringify(result, null, 2));
}