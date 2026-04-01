import type { OpenClawConfig } from "openclaw/plugin-sdk/config-runtime";
import * as providerAuth from "openclaw/plugin-sdk/provider-auth-runtime";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  registerProviderPlugin,
  requireRegisteredProvider,
} from "../../test/helpers/plugins/provider-registration.js";
import { buildOpenAIImageGenerationProvider } from "./image-generation-provider.js";
import plugin from "./index.js";

const runtimeMocks = vi.hoisted(() => ({
  ensureGlobalUndiciEnvProxyDispatcher: vi.fn(),
  refreshOpenAICodexToken: vi.fn(),
}));

vi.mock("openclaw/plugin-sdk/runtime-env", () => ({
  ensureGlobalUndiciEnvProxyDispatcher: runtimeMocks.ensureGlobalUndiciEnvProxyDispatcher,
}));

vi.mock("@mariozechner/pi-ai/oauth", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@mariozechner/pi-ai/oauth")>();
  return {
    ...actual,
    refreshOpenAICodexToken: runtimeMocks.refreshOpenAICodexToken,
  };
});

import { refreshOpenAICodexToken } from "./openai-codex-provider.runtime.js";

<<<<<<< HEAD
const OPENAI_API_KEY = process.env.OPENAI_API_KEY ?? "";
const LIVE_MODEL_ID = process.env.OPENCLAW_LIVE_OPENAI_PLUGIN_MODEL?.trim() || "gpt-5.4-nano";
const LIVE_IMAGE_MODEL = process.env.OPENCLAW_LIVE_OPENAI_IMAGE_MODEL?.trim() || "gpt-image-1";
const LIVE_VISION_MODEL = process.env.OPENCLAW_LIVE_OPENAI_VISION_MODEL?.trim() || "gpt-4.1-mini";
const liveEnabled = OPENAI_API_KEY.trim().length > 0 && process.env.OPENCLAW_LIVE_TEST === "1";
const describeLive = liveEnabled ? describe : describe.skip;
const EMPTY_AUTH_STORE = { version: 1, profiles: {} } as const;

function resolveTemplateModelId(modelId: string) {
  switch (modelId) {
    case "gpt-5.4":
      return "gpt-5.2";
    case "gpt-5.4-mini":
      return "gpt-5-mini";
    case "gpt-5.4-nano":
      return "gpt-5-nano";
    default:
      throw new Error(`Unsupported live OpenAI plugin model: ${modelId}`);
  }
}

function createTemplateModelRegistry(modelId: string): ModelRegistry {
  const registry = ModelRegistry.inMemory(AuthStorage.inMemory());
  const template = getModel("openai", resolveTemplateModelId(modelId));
  registry.registerProvider("openai", {
    apiKey: "test",
    baseUrl: template.baseUrl,
    models: [
      {
        id: template.id,
        name: template.name,
        api: template.api,
        reasoning: template.reasoning,
        input: template.input,
        cost: template.cost,
        contextWindow: template.contextWindow,
        maxTokens: template.maxTokens,
        ...(template.compat ? { compat: template.compat } : {}),
      },
    ],
  });
  return registry;
}

=======
>>>>>>> main
const registerOpenAIPlugin = () =>
  registerProviderPlugin({
    plugin,
    id: "openai",
    name: "OpenAI Provider",
  });

describe("openai plugin", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("generates PNG buffers from the OpenAI Images API", async () => {
    const resolveApiKeySpy = vi.spyOn(providerAuth, "resolveApiKeyForProvider").mockResolvedValue({
      apiKey: "sk-test",
      source: "env",
      mode: "api-key",
    });
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        data: [
          {
            b64_json: Buffer.from("png-data").toString("base64"),
            revised_prompt: "revised",
          },
        ],
      }),
    });
    vi.stubGlobal("fetch", fetchMock);

    const provider = buildOpenAIImageGenerationProvider();
    const authStore = { version: 1, profiles: {} };
    const result = await provider.generateImage({
      provider: "openai",
      model: "gpt-image-1",
      prompt: "draw a cat",
      cfg: {},
      authStore,
    });

    expect(resolveApiKeySpy).toHaveBeenCalledWith(
      expect.objectContaining({
        provider: "openai",
        store: authStore,
      }),
    );
    expect(fetchMock).toHaveBeenCalledWith(
      "https://api.openai.com/v1/images/generations",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({
          model: "gpt-image-1",
          prompt: "draw a cat",
          n: 1,
          size: "1024x1024",
        }),
      }),
    );
    expect(result).toEqual({
      images: [
        {
          buffer: Buffer.from("png-data"),
          mimeType: "image/png",
          fileName: "image-1.png",
          revisedPrompt: "revised",
        },
      ],
      model: "gpt-image-1",
    });
  });

  it("rejects reference-image edits for now", async () => {
    const provider = buildOpenAIImageGenerationProvider();

    await expect(
      provider.generateImage({
        provider: "openai",
        model: "gpt-image-1",
        prompt: "Edit this image",
        cfg: {},
        inputImages: [{ buffer: Buffer.from("x"), mimeType: "image/png" }],
      }),
    ).rejects.toThrow("does not support reference-image edits");
  });

  it("bootstraps the env proxy dispatcher before refreshing codex oauth credentials", async () => {
    const refreshed = {
      access: "next-access",
      refresh: "next-refresh",
      expires: Date.now() + 60_000,
    };
    runtimeMocks.refreshOpenAICodexToken.mockResolvedValue(refreshed);

    await expect(refreshOpenAICodexToken("refresh-token")).resolves.toBe(refreshed);

    expect(runtimeMocks.ensureGlobalUndiciEnvProxyDispatcher).toHaveBeenCalledOnce();
    expect(runtimeMocks.refreshOpenAICodexToken).toHaveBeenCalledOnce();
    expect(
      runtimeMocks.ensureGlobalUndiciEnvProxyDispatcher.mock.invocationCallOrder[0],
    ).toBeLessThan(runtimeMocks.refreshOpenAICodexToken.mock.invocationCallOrder[0]);
  });
});
