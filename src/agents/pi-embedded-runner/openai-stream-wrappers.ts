import type { StreamFn } from "@mariozechner/pi-agent-core";
import type { SimpleStreamOptions } from "@mariozechner/pi-ai";
import { streamSimple } from "@mariozechner/pi-ai";
<<<<<<< HEAD
import { resolveProviderAttributionHeaders } from "../provider-attribution.js";
=======
import type { OpenClawConfig } from "../../config/config.js";
import {
  patchCodexNativeWebSearchPayload,
  resolveCodexNativeSearchActivation,
} from "../codex-native-web-search.js";
import {
  applyOpenAIResponsesPayloadPolicy,
  resolveOpenAIResponsesPayloadPolicy,
} from "../openai-responses-payload-policy.js";
import { resolveProviderRequestPolicyConfig } from "../provider-request-config.js";
>>>>>>> main
import { log } from "./logger.js";
import { streamWithPayloadPatch } from "./stream-payload-utils.js";

type OpenAIServiceTier = "auto" | "default" | "flex" | "priority";
type OpenAITextVerbosity = "low" | "medium" | "high";

<<<<<<< HEAD
const OPENAI_RESPONSES_APIS = new Set(["openai-responses", "azure-openai-responses"]);
const OPENAI_RESPONSES_PROVIDERS = new Set(["openai", "azure-openai", "azure-openai-responses"]);

function isDirectOpenAIBaseUrl(baseUrl: unknown): boolean {
  if (typeof baseUrl !== "string" || !baseUrl.trim()) {
    return false;
  }

  try {
    const host = new URL(baseUrl).hostname.toLowerCase();
    return (
      host === "api.openai.com" || host === "chatgpt.com" || host.endsWith(".openai.azure.com")
    );
  } catch {
    const normalized = baseUrl.toLowerCase();
    return (
      normalized.includes("api.openai.com") ||
      normalized.includes("chatgpt.com") ||
      normalized.includes(".openai.azure.com")
    );
  }
}

function isOpenAIPublicApiBaseUrl(baseUrl: unknown): boolean {
  if (typeof baseUrl !== "string" || !baseUrl.trim()) {
    return false;
  }

  try {
    return new URL(baseUrl).hostname.toLowerCase() === "api.openai.com";
  } catch {
    return baseUrl.toLowerCase().includes("api.openai.com");
  }
}

function isOpenAICodexBaseUrl(baseUrl: unknown): boolean {
  if (typeof baseUrl !== "string" || !baseUrl.trim()) {
    return false;
  }

  try {
    return new URL(baseUrl).hostname.toLowerCase() === "chatgpt.com";
  } catch {
    return baseUrl.toLowerCase().includes("chatgpt.com");
  }
}

function shouldApplyOpenAIAttributionHeaders(model: {
=======
function resolveOpenAIRequestCapabilities(model: {
>>>>>>> main
  api?: unknown;
  provider?: unknown;
  baseUrl?: unknown;
  compat?: { supportsStore?: boolean };
}) {
  return resolveProviderRequestPolicyConfig({
    provider: typeof model.provider === "string" ? model.provider : undefined,
    api: typeof model.api === "string" ? model.api : undefined,
    baseUrl: typeof model.baseUrl === "string" ? model.baseUrl : undefined,
    compat: model.compat,
    capability: "llm",
    transport: "stream",
  }).capabilities;
}

function shouldApplyOpenAIAttributionHeaders(model: {
  api?: unknown;
  provider?: unknown;
  baseUrl?: unknown;
}): "openai" | "openai-codex" | undefined {
  const attributionProvider = resolveOpenAIRequestCapabilities(model).attributionProvider;
  return attributionProvider === "openai" || attributionProvider === "openai-codex"
    ? attributionProvider
    : undefined;
}

function shouldApplyOpenAIServiceTier(model: {
  api?: unknown;
  provider?: unknown;
  baseUrl?: unknown;
}): boolean {
  return resolveOpenAIResponsesPayloadPolicy(model, { storeMode: "disable" }).allowsServiceTier;
}

<<<<<<< HEAD
function applyOpenAIResponsesPayloadOverrides(params: {
  payloadObj: Record<string, unknown>;
  forceStore: boolean;
  stripStore: boolean;
  stripPromptCache: boolean;
  useServerCompaction: boolean;
  compactThreshold: number;
}): void {
  if (params.forceStore) {
    params.payloadObj.store = true;
  }
  if (params.stripStore) {
    delete params.payloadObj.store;
  }
  if (params.stripPromptCache) {
    delete params.payloadObj.prompt_cache_key;
    delete params.payloadObj.prompt_cache_retention;
  }
  if (params.useServerCompaction && params.payloadObj.context_management === undefined) {
    params.payloadObj.context_management = [
      {
        type: "compaction",
        compact_threshold: params.compactThreshold,
      },
    ];
  }
=======
function shouldApplyOpenAIReasoningCompatibility(model: {
  api?: unknown;
  provider?: unknown;
  baseUrl?: unknown;
}): boolean {
  if (typeof model.api !== "string" || typeof model.provider !== "string") {
    return false;
  }
  return resolveOpenAIRequestCapabilities(model).supportsOpenAIReasoningCompatPayload;
>>>>>>> main
}

function normalizeOpenAIServiceTier(value: unknown): OpenAIServiceTier | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const normalized = value.trim().toLowerCase();
  if (
    normalized === "auto" ||
    normalized === "default" ||
    normalized === "flex" ||
    normalized === "priority"
  ) {
    return normalized;
  }
  return undefined;
}

export function resolveOpenAIServiceTier(
  extraParams: Record<string, unknown> | undefined,
): OpenAIServiceTier | undefined {
  const raw = extraParams?.serviceTier ?? extraParams?.service_tier;
  const normalized = normalizeOpenAIServiceTier(raw);
  if (raw !== undefined && normalized === undefined) {
    const rawSummary = typeof raw === "string" ? raw : typeof raw;
    log.warn(`ignoring invalid OpenAI service tier param: ${rawSummary}`);
  }
  return normalized;
}

function normalizeOpenAITextVerbosity(value: unknown): OpenAITextVerbosity | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const normalized = value.trim().toLowerCase();
  if (normalized === "low" || normalized === "medium" || normalized === "high") {
    return normalized;
  }
  return undefined;
}

export function resolveOpenAITextVerbosity(
  extraParams: Record<string, unknown> | undefined,
): OpenAITextVerbosity | undefined {
  const raw = extraParams?.textVerbosity ?? extraParams?.text_verbosity;
  const normalized = normalizeOpenAITextVerbosity(raw);
  if (raw !== undefined && normalized === undefined) {
    const rawSummary = typeof raw === "string" ? raw : typeof raw;
    log.warn(`ignoring invalid OpenAI text verbosity param: ${rawSummary}`);
  }
  return normalized;
}

function normalizeOpenAIFastMode(value: unknown): boolean | undefined {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value !== "string") {
    return undefined;
  }
  const normalized = value.trim().toLowerCase();
  if (
    normalized === "on" ||
    normalized === "true" ||
    normalized === "yes" ||
    normalized === "1" ||
    normalized === "fast"
  ) {
    return true;
  }
  if (
    normalized === "off" ||
    normalized === "false" ||
    normalized === "no" ||
    normalized === "0" ||
    normalized === "normal"
  ) {
    return false;
  }
  return undefined;
}

export function resolveOpenAIFastMode(
  extraParams: Record<string, unknown> | undefined,
): boolean | undefined {
  const raw = extraParams?.fastMode ?? extraParams?.fast_mode;
  const normalized = normalizeOpenAIFastMode(raw);
  if (raw !== undefined && normalized === undefined) {
    const rawSummary = typeof raw === "string" ? raw : typeof raw;
    log.warn(`ignoring invalid OpenAI fast mode param: ${rawSummary}`);
  }
  return normalized;
}

function applyOpenAIFastModePayloadOverrides(params: {
  payloadObj: Record<string, unknown>;
  model: { provider?: unknown; id?: unknown; baseUrl?: unknown; api?: unknown };
}): void {
  if (params.payloadObj.service_tier === undefined && shouldApplyOpenAIServiceTier(params.model)) {
    params.payloadObj.service_tier = "priority";
  }
}

export function createOpenAIResponsesContextManagementWrapper(
  baseStreamFn: StreamFn | undefined,
  extraParams: Record<string, unknown> | undefined,
): StreamFn {
  const underlying = baseStreamFn ?? streamSimple;
  return (model, context, options) => {
    const policy = resolveOpenAIResponsesPayloadPolicy(model, {
      extraParams,
      enablePromptCacheStripping: true,
      enableServerCompaction: true,
      storeMode: "provider-policy",
    });
    if (
      policy.explicitStore === undefined &&
      !policy.useServerCompaction &&
      !policy.shouldStripStore &&
      !policy.shouldStripPromptCache &&
      !policy.shouldStripDisabledReasoningPayload
    ) {
      return underlying(model, context, options);
    }

    const originalOnPayload = options?.onPayload;
    return underlying(model, context, {
      ...options,
      onPayload: (payload) => {
        if (payload && typeof payload === "object") {
          applyOpenAIResponsesPayloadPolicy(payload as Record<string, unknown>, policy);
        }
        return originalOnPayload?.(payload, model);
      },
    });
  };
}

<<<<<<< HEAD
=======
export function createOpenAIReasoningCompatibilityWrapper(
  baseStreamFn: StreamFn | undefined,
): StreamFn {
  const underlying = baseStreamFn ?? streamSimple;
  return (model, context, options) => {
    if (!shouldApplyOpenAIReasoningCompatibility(model)) {
      return underlying(model, context, options);
    }
    return streamWithPayloadPatch(underlying, model, context, options, (payloadObj) => {
      applyOpenAIResponsesPayloadPolicy(
        payloadObj,
        resolveOpenAIResponsesPayloadPolicy(model, { storeMode: "preserve" }),
      );
    });
  };
}

>>>>>>> main
export function createOpenAIFastModeWrapper(baseStreamFn: StreamFn | undefined): StreamFn {
  const underlying = baseStreamFn ?? streamSimple;
  return (model, context, options) => {
    if (
      (model.api !== "openai-responses" &&
        model.api !== "openai-codex-responses" &&
        model.api !== "azure-openai-responses") ||
      (model.provider !== "openai" && model.provider !== "openai-codex")
    ) {
      return underlying(model, context, options);
    }
    const originalOnPayload = options?.onPayload;
    return underlying(model, context, {
      ...options,
      onPayload: (payload) => {
        if (payload && typeof payload === "object") {
          applyOpenAIFastModePayloadOverrides({
            payloadObj: payload as Record<string, unknown>,
            model,
          });
        }
        return originalOnPayload?.(payload, model);
      },
    });
  };
}

export function createOpenAIServiceTierWrapper(
  baseStreamFn: StreamFn | undefined,
  serviceTier: OpenAIServiceTier,
): StreamFn {
  const underlying = baseStreamFn ?? streamSimple;
  return (model, context, options) => {
    if (!shouldApplyOpenAIServiceTier(model)) {
      return underlying(model, context, options);
    }
    return streamWithPayloadPatch(underlying, model, context, options, (payloadObj) => {
      if (payloadObj.service_tier === undefined) {
        payloadObj.service_tier = serviceTier;
      }
    });
  };
}

export function createOpenAITextVerbosityWrapper(
  baseStreamFn: StreamFn | undefined,
  verbosity: OpenAITextVerbosity,
): StreamFn {
  const underlying = baseStreamFn ?? streamSimple;
  return (model, context, options) => {
    if (model.api !== "openai-responses" && model.api !== "openai-codex-responses") {
      return underlying(model, context, options);
    }
    const shouldOverrideExistingVerbosity = model.api === "openai-codex-responses";
    const originalOnPayload = options?.onPayload;
    return underlying(model, context, {
      ...options,
      onPayload: (payload) => {
        if (payload && typeof payload === "object") {
          const payloadObj = payload as Record<string, unknown>;
          const existingText =
            payloadObj.text && typeof payloadObj.text === "object"
              ? (payloadObj.text as Record<string, unknown>)
              : {};
          if (shouldOverrideExistingVerbosity || existingText.verbosity === undefined) {
            payloadObj.text = { ...existingText, verbosity };
          }
        }
        return originalOnPayload?.(payload, model);
      },
    });
  };
}

export function createCodexDefaultTransportWrapper(baseStreamFn: StreamFn | undefined): StreamFn {
  const underlying = baseStreamFn ?? streamSimple;
  return (model, context, options) =>
    underlying(model, context, {
      ...options,
      transport: options?.transport ?? "auto",
    });
}

export function createOpenAIDefaultTransportWrapper(baseStreamFn: StreamFn | undefined): StreamFn {
  const underlying = baseStreamFn ?? streamSimple;
  return (model, context, options) => {
    const typedOptions = options as
      | (SimpleStreamOptions & { openaiWsWarmup?: boolean })
      | undefined;
    const mergedOptions = {
      ...options,
      transport: options?.transport ?? "auto",
      openaiWsWarmup: typedOptions?.openaiWsWarmup ?? true,
    } as SimpleStreamOptions;
    return underlying(model, context, mergedOptions);
  };
}

export function createOpenAIAttributionHeadersWrapper(
  baseStreamFn: StreamFn | undefined,
): StreamFn {
  const underlying = baseStreamFn ?? streamSimple;
  return (model, context, options) => {
    const attributionProvider = shouldApplyOpenAIAttributionHeaders(model);
    if (!attributionProvider) {
      return underlying(model, context, options);
    }
    return underlying(model, context, {
      ...options,
      headers: resolveProviderRequestPolicyConfig({
        provider: attributionProvider,
        api: typeof model.api === "string" ? model.api : undefined,
        baseUrl: typeof model.baseUrl === "string" ? model.baseUrl : undefined,
        capability: "llm",
        transport: "stream",
        callerHeaders: options?.headers,
        precedence: "defaults-win",
      }).headers,
    });
  };
}
