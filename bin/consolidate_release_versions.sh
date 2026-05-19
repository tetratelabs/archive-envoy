#!/usr/bin/env bash

# Copyright Archive Envoy
# SPDX-License-Identifier: Apache-2.0
# The full text of the Apache license is available in the LICENSE file at
# the root of the repo.

set -ue

# This creates a json file including all archived releases of a GitHub Repository.
# Notably, this rewrites tarballURLs as permalinks

# Ensure we have tools we need installed
curl --version >/dev/null
jq --version >/dev/null
curl="curl -fsSL"

# A valid GitHub token to avoid rate limiting.
githubToken=${GITHUB_TOKEN:-}
# Prepare authorization header when performing request to api.github.com to avoid rate limiting, especially when testing locally.
authorizationHeader="Authorization: Bearer ${githubToken}"

githubRepo="${1?-githubRepo required ex tetratelabs/archive-envoy}"
downloadBaseURL="${2?-downloadBaseURL required ex https://archive.tetratelabs.io/envoy/download}"
case "${3:-0}" in
0) debugVersion='' ;;
1) debugVersion='1' ;;
*) echo >&2 "debugVersion, if present, should be '', '0', or '1'" && exit 1 ;;
esac

# This must match netlify.toml redirects
redirectsTo="https://github.com/${githubRepo}/releases/download"

# Fetch the last page number of releases (example value: 7), so we can get all of the releases.
# To get the last page, we send a HEAD request to "https://api.github.com/repos/${githubRepo}/releases",
# then "grep" the "link" header value.
# Reference: https://docs.github.com/en/rest/guides/using-pagination-in-the-rest-api?apiVersion=2022-11-28#using-link-headers.
lastReleasePage=$(${curl}I ${githubToken:+ -H "${authorizationHeader}"} "https://api.github.com/repos/${githubRepo}/releases" |
  grep -Eo 'page=[0-9]+' | awk 'NR==2' | cut -d'=' -f2)
lastReleasePage=${lastReleasePage:-1}

# archive all dists for the version, generating the envoy-versions.json format incrementally
releaseVersions="{}"

for ((page = 1; page <= lastReleasePage; page++)); do
  # dev and dev_debug are prereleases, so they need explicit name matching to pass the filter.
  versions=$(${curl} ${githubToken:+ -H "${authorizationHeader}"} "https://api.github.com/repos/${githubRepo}/releases?page=${page}" |
    jq -er ".|map(select((.prerelease == false and .draft == false) or .name == \"dev\" or .name == \"dev_debug\"))|.[]|.name" | sort -n) || exit 1

  for version in ${versions}; do
    # Exclusively handle debug.
    case ${version} in v[0-9]*[0-9]_debug|dev_debug) nextDebugVersion=1 ;; *) unset nextDebugVersion;; esac
    [ "${debugVersion:-}" != "${nextDebugVersion:-}" ] && continue

    versionsUrl="${redirectsTo}/${version}/envoy-${version}.json"
    nextReleaseVersion=$(${curl} "${versionsUrl}" | sed "s~${redirectsTo}~${downloadBaseURL}~g") || exit 1
    # merge the pending releaseVersions json to include the next one.
    releaseVersions=$(echo "${releaseVersions}" "${nextReleaseVersion}" | jq -Sse '.[0] * .[1]')
  done
done

# reorder top-level keys so that versions appear before sha256sums
echo "${releaseVersions}" |\
  jq '. | .latestVersion = ( .versions | keys | sort_by(split(".") | map(tonumber)) | last )' |\
  jq '{latestVersion, versions, sha256sums} + (if .dev then {dev} else {} end)'
