#!/usr/bin/env bash

# Copyright archive-envoy contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Report one stable OSS Envoy release to patch-service.
#
# Usage: notify_patch_service.sh v1.39.0
# Env:   PATCH_SERVICE_TOKEN  token with write access to tetrateio/patch-service
#        DRY_RUN=true         print the payload instead of dispatching it
# Local: DRY_RUN=true ./bin/notify_patch_service.sh v1.39.0
#
# Patch-service creates manifests/envoy.json on the first dispatch because this
# script always supplies explicit image refs. It then resolves platform digests
# and opens the manifest change as a pull request.
#
# Example output:
# {
#   "event_type": "update-manifest",
#   "client_payload": {
#     "component": "envoy",
#     "version": "1.39.0",
#     "releaseDate": "2026-07-14",
#     "latest": true,
#     "images": "{\"contrib-debug\":\"docker.io/envoyproxy/envoy:contrib-debug-v1.39.0\",\"contrib-distroless\":\"docker.io/envoyproxy/envoy:contrib-distroless-v1.39.0\",\"contrib\":\"docker.io/envoyproxy/envoy:contrib-v1.39.0\",\"debug\":\"docker.io/envoyproxy/envoy:debug-v1.39.0\",\"distroless\":\"docker.io/envoyproxy/envoy:distroless-v1.39.0\",\"google-vrp\":\"docker.io/envoyproxy/envoy:google-vrp-v1.39.0\",\"tools\":\"docker.io/envoyproxy/envoy:tools-v1.39.0\",\"envoy\":\"docker.io/envoyproxy/envoy:v1.39.0\"}"
#   }
# }

versionTag=${1?version tag is required, e.g. v1.39.0}
if [[ ! "${versionTag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo >&2 "version tag must be a stable Envoy release, e.g. v1.39.0"
  exit 1
fi

case ${DRY_RUN:-false} in
true|false) dryRun=${DRY_RUN:-false} ;;
*) echo >&2 "DRY_RUN must be true or false"; exit 1 ;;
esac

for tool in curl docker gh jq; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo >&2 "${tool} is required"
    exit 1
  fi
done

releaseDate=$(gh api \
  "repos/envoyproxy/envoy/releases/tags/${versionTag}" \
  --jq '.published_at[0:10]')

# Envoy publishes maintenance releases for several minor lines together. Record
# all of them, but only let the highest stable version advance latestVersion.
latestVersionTag=$(gh release list \
  --repo envoyproxy/envoy \
  --exclude-drafts \
  --exclude-pre-releases \
  --limit 100 \
  --json tagName |
  jq -er '
    [.[] | .tagName | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))]
    | sort_by(ltrimstr("v") | split(".") | map(tonumber))
    | last
  ')
latest=false
if [[ "${versionTag}" == "${latestVersionTag}" ]]; then
  latest=true
fi

# Query Docker Hub rather than hard-coding the current variant set. Maintained
# Envoy branches do not all publish the same variants, and new ones can be added.
tags='[]'
tagsURL="https://hub.docker.com/v2/repositories/envoyproxy/envoy/tags?page_size=100&name=${versionTag}"
while [[ -n "${tagsURL}" ]]; do
  response=$(curl -fsSL "${tagsURL}")
  tags=$(jq -nc \
    --argjson found "${tags}" \
    --argjson page "$(jq '[.results[].name]' <<<"${response}")" \
    '$found + $page')
  tagsURL=$(jq -r '.next // empty' <<<"${response}")
done

# Exact release tags are either the bare version (the default Envoy image) or
# a named variant followed by the version. Floating minor tags are excluded.
releaseTags=$(jq -c --arg version "${versionTag}" '
  [.[] | select(. == $version or endswith("-" + $version))] | unique
' <<<"${tags}")
if [[ $(jq 'length' <<<"${releaseTags}") -eq 0 ]]; then
  echo >&2 "no Docker images found for ${versionTag}"
  exit 1
fi

images='{}'
while IFS= read -r tag; do
  variant=${tag%"-${versionTag}"}
  if [[ "${tag}" == "${versionTag}" ]]; then
    variant=envoy
  fi
  image="docker.io/envoyproxy/envoy:${tag}"

  # Patch-service resolves platform digests, but checking here keeps a partial
  # or stale Docker Hub result from producing a manifest update proposal.
  if ! docker buildx imagetools inspect "${image}" >/dev/null; then
    echo >&2 "cannot resolve ${image}"
    exit 1
  fi

  images=$(jq -nc \
    --argjson images "${images}" \
    --arg variant "${variant}" \
    --arg image "${image}" \
    '$images + {($variant): $image}')
done < <(jq -r '.[]' <<<"${releaseTags}")

if ! jq -e 'has("distroless")' <<<"${images}" >/dev/null; then
  echo >&2 "the distroless image required by Envoy Gateway is not published"
  exit 1
fi

payload=$(jq -nc \
  --arg version "${versionTag#v}" \
  --arg releaseDate "${releaseDate}" \
  --argjson latest "${latest}" \
  --arg images "${images}" \
  '{
    event_type: "update-manifest",
    client_payload: {
      component: "envoy",
      version: $version,
      releaseDate: $releaseDate,
      latest: $latest,
      images: $images
    }
  }')

if [[ "${dryRun}" == true ]]; then
  jq . <<<"${payload}"
  exit 0
fi

patchServiceToken=${PATCH_SERVICE_TOKEN:-${GH_TOKEN:-}}
if [[ -z "${patchServiceToken}" ]]; then
  echo >&2 "PATCH_SERVICE_TOKEN is required to dispatch to patch-service"
  exit 1
fi

curl -fsSL -X POST \
  -H "Authorization: Bearer ${patchServiceToken}" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/tetrateio/patch-service/dispatches \
  -d "${payload}"

echo "reported Envoy ${versionTag} to patch-service"
