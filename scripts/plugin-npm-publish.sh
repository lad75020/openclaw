#!/usr/bin/env bash

set -euo pipefail

mode="${1:-}"
package_dir="${2:-}"

if [[ "${mode}" != "--dry-run" && "${mode}" != "--publish" ]]; then
  echo "usage: bash scripts/plugin-npm-publish.sh [--dry-run|--publish] <package-dir>" >&2
  exit 2
fi

if [[ -z "${package_dir}" ]]; then
  echo "missing package dir" >&2
  exit 2
fi

package_name="$(node -e 'const pkg = require(require("node:path").resolve(process.argv[1], "package.json")); console.log(pkg.name)' "${package_dir}")"
package_version="$(node -e 'const pkg = require(require("node:path").resolve(process.argv[1], "package.json")); console.log(pkg.version)' "${package_dir}")"
current_beta_version="$(npm view "${package_name}" dist-tags.beta 2>/dev/null || true)"
<<<<<<< HEAD
mapfile -t publish_plan < <(
  PACKAGE_VERSION="${package_version}" CURRENT_BETA_VERSION="${current_beta_version}" node --input-type=module <<'EOF'
import { resolveNpmPublishPlan } from "./scripts/lib/npm-publish-plan.mjs";
=======
publish_plan_output="$(
  PACKAGE_VERSION="${package_version}" CURRENT_BETA_VERSION="${current_beta_version}" PUBLISH_MODE="${mode}" node --input-type=module <<'EOF'
import {
  resolveNpmDistTagMirrorAuth,
  resolveNpmPublishPlan,
  shouldRequireNpmDistTagMirrorAuth,
} from "./scripts/lib/npm-publish-plan.mjs";
>>>>>>> main

const plan = resolveNpmPublishPlan(
  process.env.PACKAGE_VERSION ?? "",
  process.env.CURRENT_BETA_VERSION,
);
<<<<<<< HEAD
console.log(plan.channel);
console.log(plan.publishTag);
console.log(plan.mirrorDistTags.join(","));
EOF
)

release_channel="${publish_plan[0]}"
publish_tag="${publish_plan[1]}"
mirror_dist_tags_csv="${publish_plan[2]:-}"
=======
const auth = resolveNpmDistTagMirrorAuth({
  nodeAuthToken: process.env.NODE_AUTH_TOKEN,
  npmToken: process.env.NPM_TOKEN,
});
const shouldRequireMirrorAuth = shouldRequireNpmDistTagMirrorAuth({
  mode: process.env.PUBLISH_MODE === "--publish" ? "--publish" : "--dry-run",
  mirrorDistTags: plan.mirrorDistTags,
  hasAuth: auth.hasAuth,
});
console.log(plan.channel);
console.log(plan.publishTag);
console.log(plan.mirrorDistTags.join(","));
console.log(auth.source);
console.log(shouldRequireMirrorAuth ? "required" : "optional");
EOF
)"
release_channel="$(printf '%s\n' "${publish_plan_output}" | sed -n '1p')"
publish_tag="$(printf '%s\n' "${publish_plan_output}" | sed -n '2p')"
mirror_dist_tags_csv="$(printf '%s\n' "${publish_plan_output}" | sed -n '3p')"
mirror_auth_source="$(printf '%s\n' "${publish_plan_output}" | sed -n '4p')"
mirror_auth_requirement="$(printf '%s\n' "${publish_plan_output}" | sed -n '5p')"
mirror_auth_source="${mirror_auth_source:-none}"
mirror_auth_requirement="${mirror_auth_requirement:-optional}"
>>>>>>> main
publish_cmd=(npm publish --access public --tag "${publish_tag}" --provenance)

echo "Resolved package dir: ${package_dir}"
echo "Resolved package name: ${package_name}"
echo "Resolved package version: ${package_version}"
echo "Current beta dist-tag: ${current_beta_version:-<missing>}"
echo "Resolved release channel: ${release_channel}"
echo "Resolved publish tag: ${publish_tag}"
echo "Resolved mirror dist-tags: ${mirror_dist_tags_csv:-<none>}"
echo "Publish auth: GitHub OIDC trusted publishing"
<<<<<<< HEAD
=======
echo "Mirror dist-tag auth source: ${mirror_auth_source}"
echo "Mirror dist-tag auth requirement: ${mirror_auth_requirement}"

mirror_auth_token=""
case "${mirror_auth_source}" in
  node-auth-token)
    mirror_auth_token="${NODE_AUTH_TOKEN:-}"
    ;;
  npm-token)
    mirror_auth_token="${NPM_TOKEN:-}"
    ;;
esac

if [[ "${mirror_auth_requirement}" == "required" && -z "${mirror_auth_token}" ]]; then
  echo "npm dist-tag mirroring requires explicit npm auth via NODE_AUTH_TOKEN or NPM_TOKEN." >&2
  echo "Refusing publish before npm latest/beta promotion can diverge." >&2
  exit 1
fi
>>>>>>> main

printf 'Publish command:'
printf ' %q' "${publish_cmd[@]}"
printf '\n'

if [[ "${mode}" == "--dry-run" ]]; then
  exit 0
fi

(
  cd "${package_dir}"
  "${publish_cmd[@]}"

  if [[ -n "${mirror_dist_tags_csv}" ]]; then
    IFS=',' read -r -a mirror_dist_tags <<< "${mirror_dist_tags_csv}"
    for dist_tag in "${mirror_dist_tags[@]}"; do
      [[ -n "${dist_tag}" ]] || continue
      echo "Mirroring ${package_name}@${package_version} onto dist-tag ${dist_tag}"
      npm dist-tag add "${package_name}@${package_version}" "${dist_tag}"
    done
  fi
)
