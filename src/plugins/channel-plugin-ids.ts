import { listPotentialConfiguredChannelIds } from "../channels/config-presence.js";
import type { OpenClawConfig } from "../config/config.js";
import {
  createPluginActivationSource,
  normalizePluginsConfig,
  resolveEffectivePluginActivationState,
} from "./config-state.js";
import { loadPluginManifestRegistry, type PluginManifestRecord } from "./manifest-registry.js";
import { hasKind } from "./slots.js";

function hasRuntimeContractSurface(plugin: PluginManifestRecord): boolean {
  return Boolean(
    plugin.providers.length > 0 ||
    plugin.cliBackends.length > 0 ||
    plugin.contracts?.speechProviders?.length ||
    plugin.contracts?.mediaUnderstandingProviders?.length ||
    plugin.contracts?.imageGenerationProviders?.length ||
    plugin.contracts?.videoGenerationProviders?.length ||
    plugin.contracts?.webFetchProviders?.length ||
    plugin.contracts?.webSearchProviders?.length ||
    plugin.contracts?.memoryEmbeddingProviders?.length ||
    hasKind(plugin.kind, "memory"),
  );
}

<<<<<<< HEAD
function addProviderModelPairActivationId(params: {
  provider: string | undefined;
  model: string | undefined;
  activationIds: Set<string>;
}): void {
  const provider = normalizeProviderId(params.provider ?? "");
  const model = params.model?.trim();
  if (!provider || !model) {
    return;
  }
  params.activationIds.add(provider);
}

function collectConfiguredActivationIds(config: OpenClawConfig): Set<string> {
  const activationIds = new Set<string>();
  const aliasIndex = buildModelAliasIndex({
    cfg: config,
    defaultProvider: DEFAULT_PROVIDER,
  });

  addModelListActivationIds({ value: config.agents?.defaults?.model, activationIds, aliasIndex });
  addModelListActivationIds({
    value: config.agents?.defaults?.imageModel,
    activationIds,
    aliasIndex,
  });
  addModelListActivationIds({
    value: config.agents?.defaults?.imageGenerationModel,
    activationIds,
    aliasIndex,
  });
  addModelListActivationIds({
    value: config.agents?.defaults?.pdfModel,
    activationIds,
    aliasIndex,
  });
  addResolvedActivationId({
    raw: config.agents?.defaults?.compaction?.model,
    activationIds,
    aliasIndex,
  });
  addResolvedActivationId({
    raw: config.agents?.defaults?.heartbeat?.model,
    activationIds,
    aliasIndex,
  });
  addModelListActivationIds({
    value: config.agents?.defaults?.subagents?.model,
    activationIds,
    aliasIndex,
  });
  addResolvedActivationId({
    raw: config.messages?.tts?.summaryModel,
    activationIds,
    aliasIndex,
  });
  addResolvedActivationId({
    raw: config.hooks?.gmail?.model,
    activationIds,
    aliasIndex,
  });

  for (const modelRef of Object.keys(config.agents?.defaults?.models ?? {})) {
    addResolvedActivationId({
      raw: modelRef,
      activationIds,
      aliasIndex,
    });
  }

  for (const providerId of Object.keys(config.agents?.defaults?.cliBackends ?? {})) {
    const normalized = normalizeProviderId(providerId);
    if (normalized) {
      activationIds.add(normalized);
    }
  }

  for (const providerId of Object.keys(config.models?.providers ?? {})) {
    const normalized = normalizeProviderId(providerId);
    if (normalized) {
      activationIds.add(normalized);
    }
  }

  for (const agent of config.agents?.list ?? []) {
    addModelListActivationIds({ value: agent.model, activationIds, aliasIndex });
    addModelListActivationIds({ value: agent.subagents?.model, activationIds, aliasIndex });
    addResolvedActivationId({
      raw: agent.heartbeat?.model,
      activationIds,
      aliasIndex,
    });
  }

  for (const mapping of config.hooks?.mappings ?? []) {
    addResolvedActivationId({
      raw: mapping.model,
      activationIds,
      aliasIndex,
    });
  }

  for (const channelMap of Object.values(config.channels?.modelByChannel ?? {})) {
    if (!channelMap || typeof channelMap !== "object") {
      continue;
    }
    for (const raw of Object.values(channelMap)) {
      addResolvedActivationId({
        raw: typeof raw === "string" ? raw : undefined,
        activationIds,
        aliasIndex,
      });
    }
  }

  addResolvedActivationId({
    raw: config.tools?.subagents?.model
      ? resolveAgentModelPrimaryValue(config.tools?.subagents?.model)
      : undefined,
    activationIds,
    aliasIndex,
  });
  if (config.tools?.subagents?.model) {
    for (const fallback of resolveAgentModelFallbackValues(config.tools.subagents.model)) {
      addResolvedActivationId({ raw: fallback, activationIds, aliasIndex });
    }
  }

  addResolvedActivationId({
    raw: config.tools?.web?.search?.gemini?.model,
    activationIds,
    aliasIndex,
  });
  addResolvedActivationId({
    raw: config.tools?.web?.search?.grok?.model,
    activationIds,
    aliasIndex,
  });
  addResolvedActivationId({
    raw: config.tools?.web?.search?.kimi?.model,
    activationIds,
    aliasIndex,
  });
  addResolvedActivationId({
    raw: config.tools?.web?.search?.perplexity?.model,
    activationIds,
    aliasIndex,
  });

  for (const entry of config.tools?.media?.models ?? []) {
    addProviderModelPairActivationId({
      provider: entry.provider,
      model: entry.model,
      activationIds,
    });
  }
  for (const entry of config.tools?.media?.image?.models ?? []) {
    addProviderModelPairActivationId({
      provider: entry.provider,
      model: entry.model,
      activationIds,
    });
  }
  for (const entry of config.tools?.media?.audio?.models ?? []) {
    addProviderModelPairActivationId({
      provider: entry.provider,
      model: entry.model,
      activationIds,
    });
  }
  for (const entry of config.tools?.media?.video?.models ?? []) {
    addProviderModelPairActivationId({
      provider: entry.provider,
      model: entry.model,
      activationIds,
    });
  }

  return activationIds;
=======
function isGatewayStartupSidecar(plugin: PluginManifestRecord): boolean {
  return plugin.channels.length === 0 && !hasRuntimeContractSurface(plugin);
>>>>>>> main
}

export function resolveChannelPluginIds(params: {
  config: OpenClawConfig;
  workspaceDir?: string;
  env: NodeJS.ProcessEnv;
}): string[] {
  return loadPluginManifestRegistry({
    config: params.config,
    workspaceDir: params.workspaceDir,
    env: params.env,
  })
    .plugins.filter((plugin) => plugin.channels.length > 0)
    .map((plugin) => plugin.id);
}

export function resolveConfiguredChannelPluginIds(params: {
  config: OpenClawConfig;
  workspaceDir?: string;
  env: NodeJS.ProcessEnv;
}): string[] {
  const configuredChannelIds = new Set(
    listPotentialConfiguredChannelIds(params.config, params.env).map((id) => id.trim()),
  );
  if (configuredChannelIds.size === 0) {
    return [];
  }
  return resolveChannelPluginIds(params).filter((pluginId) => configuredChannelIds.has(pluginId));
}

export function resolveConfiguredDeferredChannelPluginIds(params: {
  config: OpenClawConfig;
  workspaceDir?: string;
  env: NodeJS.ProcessEnv;
}): string[] {
  const configuredChannelIds = new Set(
    listPotentialConfiguredChannelIds(params.config, params.env).map((id) => id.trim()),
  );
  if (configuredChannelIds.size === 0) {
    return [];
  }
  return loadPluginManifestRegistry({
    config: params.config,
    workspaceDir: params.workspaceDir,
    env: params.env,
  })
    .plugins.filter(
      (plugin) =>
        plugin.channels.some((channelId) => configuredChannelIds.has(channelId)) &&
        plugin.startupDeferConfiguredChannelFullLoadUntilAfterListen === true,
    )
    .map((plugin) => plugin.id);
}

export function resolveGatewayStartupPluginIds(params: {
  config: OpenClawConfig;
  activationSourceConfig?: OpenClawConfig;
  workspaceDir?: string;
  env: NodeJS.ProcessEnv;
}): string[] {
  const configuredChannelIds = new Set(
    listPotentialConfiguredChannelIds(params.config, params.env).map((id) => id.trim()),
  );
  const pluginsConfig = normalizePluginsConfig(params.config.plugins);
  // Startup must classify allowlist exceptions against the raw config snapshot,
  // not the auto-enabled effective snapshot, or configured-only channels can be
  // misclassified as explicit enablement.
  const activationSource = createPluginActivationSource({
    config: params.activationSourceConfig ?? params.config,
  });
  return loadPluginManifestRegistry({
    config: params.config,
    workspaceDir: params.workspaceDir,
    env: params.env,
  })
    .plugins.filter((plugin) => {
      if (plugin.channels.some((channelId) => configuredChannelIds.has(channelId))) {
        return true;
      }
      if (!isGatewayStartupSidecar(plugin)) {
        return false;
      }
      const activationState = resolveEffectivePluginActivationState({
        id: plugin.id,
        origin: plugin.origin,
        config: pluginsConfig,
        rootConfig: params.config,
        enabledByDefault: plugin.enabledByDefault,
        activationSource,
      });
      if (!activationState.enabled) {
        return false;
      }
      if (plugin.origin !== "bundled") {
        return activationState.explicitlyEnabled;
      }
      return activationState.source === "explicit" || activationState.source === "default";
    })
    .map((plugin) => plugin.id);
}
