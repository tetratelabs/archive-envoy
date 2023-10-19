#!/usr/bin/env bash

# Copyright 2023 Tetrate
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -ue

# This checks upstrean ${sourceGitHubRepository} releases and compares it
# with the released versions on https://archive.tetratelabs.io/envoy/envoy-versions.json.

# Ensure we have tools we need installed
curl --version >/dev/null
jq --version >/dev/null
gh --version >/dev/null

sourceGitHubRepository=${1?sourceGitHubRepository is required. ex envoyproxy/envoy}
targetGitHubRepository=${2?targetGitHubRepository is required. ex tetratelabs/archive-envoy}
lowestVersion=${3?lowestVersion is required. ex 12.0.0}

curl="curl -fsSL"

# A valid GitHub token to avoid rate limiting.
githubToken=${GITHUB_TOKEN:-}
# Prepare authorization header when performing request to api.github.com to avoid rate limiting, especially when testing locally.
authorizationHeader="Authorization: Bearer ${githubToken}"

# Always use the released versions.
currentVersions=$(${curl} https://archive.tetratelabs.io/envoy/envoy-versions.json)

# Fetch the last page number of releases (example value: 7), so we can get all of the releases.
# To get the last page, we send a HEAD request to "https://api.github.com/repos/${sourceGitHubRepository}/releases",
# then "grep" the "link" header value.
# Reference: https://docs.github.com/en/rest/guides/using-pagination-in-the-rest-api?apiVersion=2022-11-28#using-link-headers.
lastReleasePage=$(${curl}I ${githubToken:+ -H "${authorizationHeader}"} "https://api.github.com/repos/${sourceGitHubRepository}/releases" |
  grep -Eo 'page=[0-9]+' | awk 'NR==2' | cut -d'=' -f2) || exit 1

for ((page = 1; page <= lastReleasePage; page++)); do
  versions=$(${curl} ${githubToken:+ -H "${authorizationHeader}"} "https://api.github.com/repos/${sourceGitHubRepository}/releases?page=${page}" |
    jq -er ".|map(select(.prerelease == false and .draft == false))|.[]|.name" | sort -n) || exit 1

  for version in ${versions}; do
    if [[ $(echo "${currentVersions}" | jq -r --arg ver "${version#v}" '.versions | has($ver)') == "true" ]]; then
      continue
    fi

    if [[ "$(echo -e "${version#v}\n${lowestVersion}" | sort -V | tail -n 1)" == "${version#v}" ]]; then
      echo "creating release for"' '"${version}"
      gh workflow run release.yaml -f version="${version}"_debug -R "${targetGitHubRepository}"
      gh workflow run release.yaml -f version="${version}" -R "${targetGitHubRepository}"
    fi

    # TODO(dio): For macOS, we still need to check for https://ghcr.io/v2/homebrew/core/envoy/tags/list and see if
    # our released JSON has darwin tarballs in it.
  done
done
