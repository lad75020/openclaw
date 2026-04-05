// Manual facade. Keep loader boundary explicit.
type FacadeModule = typeof import("@openclaw/irc/api.js");
import {
  createLazyFacadeObjectValue,
  loadBundledPluginPublicSurfaceModuleSync,
} from "./facade-runtime.js";

function loadFacadeModule(): FacadeModule {
  return loadBundledPluginPublicSurfaceModuleSync<FacadeModule>({
    dirName: "irc",
    artifactBasename: "api.js",
  });
}
export const ircSetupAdapter: FacadeModule["ircSetupAdapter"] = createLazyFacadeObjectValue(
  () => loadFacadeModule()["ircSetupAdapter"] as object,
) as FacadeModule["ircSetupAdapter"];
export const ircSetupWizard: FacadeModule["ircSetupWizard"] = createLazyFacadeObjectValue(
  () => loadFacadeModule()["ircSetupWizard"] as object,
) as FacadeModule["ircSetupWizard"];
export const listIrcAccountIds: FacadeModule["listIrcAccountIds"] = createLazyFacadeObjectValue(
  () => loadFacadeModule()["listIrcAccountIds"] as object,
) as FacadeModule["listIrcAccountIds"];
export const resolveDefaultIrcAccountId: FacadeModule["resolveDefaultIrcAccountId"] =
  createLazyFacadeObjectValue(
    () => loadFacadeModule()["resolveDefaultIrcAccountId"] as object,
  ) as FacadeModule["resolveDefaultIrcAccountId"];
export const resolveIrcAccount: FacadeModule["resolveIrcAccount"] = ((...args) =>
  loadFacadeModule()["resolveIrcAccount"](...args)) as FacadeModule["resolveIrcAccount"];
