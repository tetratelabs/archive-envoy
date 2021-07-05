#!/bin/sh -ue

# Copyright 2021 Tetrate
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

# This creates a json file including all archived releases of a GitHub Repository.
# Notably, this rewrites tarballURLs as permalinks

# Ensure we have tools we need installed
curl --version >/dev/null
jq --version >/dev/null
curl="curl -fsSL"

githubRepo="${1?-githubRepo required ex tetratelabs/archive-envoy}"
downloadBaseURL="${2?-downloadBaseURL required ex https://archive.tetratelabs.io/envoy/download}"
case "${3:-0}" in
0) debugVersion='' ;;
1) debugVersion='1' ;;
*) echo >&2 "debugVersion, if present, should be '', '0', or '1'" && exit 1 ;;
esac

# This must match netlify.toml redirects
redirectsTo="https://github.com/${githubRepo}/releases/download"

# archive all dists for the version, generating the envoy-versions.json format incrementally
releaseVersions="{}"
versions=$(${curl} "https://api.github.com/repos/${githubRepo}/releases?per_page=100" |
  jq -er ".|map(select(.prerelease == false and .draft == false))|.[]|.name" | sort -n) || exit 1

for version in ${versions}; do
  # Exclusively handle debug
  case ${version} in v[0-9]*[0-9]_debug) nextDebugVersion=1 ;; *) unset nextDebugVersion;; esac
  [ "${debugVersion:-}" != "${nextDebugVersion:-}" ] && continue

  versionsUrl="${redirectsTo}/${version}/envoy-${version}.json"
  nextReleaseVersion=$(${curl} "${versionsUrl}" | sed "s~${redirectsTo}~${downloadBaseURL}~g") || exit 1
  # merge the pending releaseVersions json to include the next one
  releaseVersions=$(echo "${releaseVersions}" "${nextReleaseVersion}" | jq -Sse '.[0] * .[1]')
done

# reorder top-level keys so that versions appear before sha256sums
echo "${releaseVersions}" | jq '{latestVersion: .latestVersion, versions: .versions, sha256sums: .sha256sums}'
