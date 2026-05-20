#!/usr/bin/env bash

# Copyright archive-envoy contributors
# SPDX-License-Identifier: Apache-2.0

set -ue

# This checks upstream ${sourceGitHubRepository} releases and compares them
# with the released versions on https://archive.tetratelabs.io/envoy/envoy-versions.json.
# When a new version is found and its Docker image is available, it triggers
# the release workflow for both production and debug builds.
#
# Fetches the 10 most recent releases via GraphQL (one API call) because
# Envoy batches at most 6 patch releases on the same day.

curl --version >/dev/null
jq --version >/dev/null
gh --version >/dev/null

sourceGitHubRepository=${1?sourceGitHubRepository is required. ex envoyproxy/envoy}
targetGitHubRepository=${2?targetGitHubRepository is required. ex tetratelabs/archive-envoy}

sourceOwner=${sourceGitHubRepository%%/*}
sourceName=${sourceGitHubRepository##*/}

docker_image_exists() {
  local image=$1 tag=$2
  local token
  token=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${image}:pull" | jq -r '.token')
  local status
  status=$(curl -fsSL -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
    "https://registry-1.docker.io/v2/${image}/manifests/${tag}" 2>/dev/null)
  [ "${status}" = "200" ]
}

versionsFile=$(mktemp)
trap 'rm -f "${versionsFile}"' EXIT
curl -fsSL https://archive.tetratelabs.io/envoy/envoy-versions.json > "${versionsFile}"

recentTags=$(gh api graphql \
  -f owner="${sourceOwner}" \
  -f name="${sourceName}" \
  -f query='
    query($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        releases(first: 10, orderBy: {field: CREATED_AT, direction: DESC}) {
          nodes { tagName isDraft isPrerelease }
        }
      }
    }
  ' --jq '[.data.repository.releases.nodes[]
    | select(.isDraft == false and .isPrerelease == false)
    | .tagName]')

newVersions=$(echo "${recentTags}" | jq -r \
  --slurpfile archive "${versionsFile}" \
  '.[] | ltrimstr("v") as $ver
   | select($archive[0].versions | has($ver) | not)
   | "v" + $ver' | sort -V)

for version in ${newVersions}; do
  if ! docker_image_exists envoyproxy/envoy "${version}"; then
    echo "skipping ${version}: Docker image not yet available"
    continue
  fi

  echo "creating release for ${version}"
  ${DRY_RUN:-} gh workflow run release.yaml -f version="${version}"_debug -R "${targetGitHubRepository}"
  ${DRY_RUN:-} gh workflow run release.yaml -f version="${version}" -R "${targetGitHubRepository}"
done
