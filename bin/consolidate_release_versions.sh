#!/usr/bin/env bash

# Copyright Archive Envoy
# SPDX-License-Identifier: Apache-2.0
# The full text of the Apache license is available in the LICENSE file at
# the root of the repo.

set -ue

# This creates a json file including all archived releases of a GitHub Repository.
# Notably, this rewrites tarball URLs as permalinks.

curl --version >/dev/null
jq --version >/dev/null
curl="curl -fsSL"

githubToken=${GITHUB_TOKEN:-}
if [ -z "${githubToken}" ]; then
  echo >&2 "GITHUB_TOKEN is required for GraphQL API access"
  exit 1
fi
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

owner="${githubRepo%%/*}"
name="${githubRepo##*/}"

# Fetch all release names via GraphQL (100 per page vs REST's 30).
graphqlQuery='query($owner:String!,$name:String!,$cursor:String){repository(owner:$owner,name:$name){releases(first:100,orderBy:{field:CREATED_AT,direction:DESC},after:$cursor){pageInfo{hasNextPage endCursor}nodes{name isDraft isPrerelease}}}}'

versions=""
cursor="null"
while true; do
  requestBody=$(jq -n \
    --arg query "${graphqlQuery}" \
    --arg owner "${owner}" \
    --arg name "${name}" \
    --argjson cursor "${cursor}" \
    '{query: $query, variables: {owner: $owner, name: $name, cursor: $cursor}}')

  response=$(${curl} -H "${authorizationHeader}" \
    -H "Content-Type: application/json" \
    -d "${requestBody}" \
    https://api.github.com/graphql) || exit 1

  errors=$(echo "${response}" | jq -r '.errors[0].message // empty')
  if [ -n "${errors}" ]; then
    echo >&2 "GraphQL error: ${errors}"
    exit 1
  fi

  versions+=$(echo "${response}" | jq -r '
    [.data.repository.releases.nodes[]
     | select((.isDraft == false and .isPrerelease == false)
           or .name == "dev" or .name == "dev_debug")
     | .name] | .[]')
  versions+=$'\n'

  hasNextPage=$(echo "${response}" | jq -r '.data.repository.releases.pageInfo.hasNextPage')
  [ "${hasNextPage}" = "true" ] || break
  cursor=$(echo "${response}" | jq '.data.repository.releases.pageInfo.endCursor')
done

versions=$(echo "${versions}" | sort -n)

# Download each version's JSON to a temp directory for a single batch merge.
tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT

for version in ${versions}; do
  case ${version} in v[0-9]*[0-9]_debug|dev_debug) nextDebugVersion=1 ;; *) unset nextDebugVersion;; esac
  [ "${debugVersion:-}" != "${nextDebugVersion:-}" ] && continue

  ${curl} "${redirectsTo}/${version}/envoy-${version}.json" > "${tmpdir}/${version}.json" || exit 1
done

# Merge all version JSONs in one pass, rewriting download URLs.
releaseVersions=$(sed "s~${redirectsTo}~${downloadBaseURL}~g" "${tmpdir}"/*.json | \
  jq -s 'reduce .[] as $x ({}; . * $x)')

echo "${releaseVersions}" |\
  jq '. | .latestVersion = ( .versions | keys | sort_by(gsub("_debug$";"") | split(".") | map(tonumber)) | last )' |\
  jq '{latestVersion, versions, sha256sums} + (if .dev then {dev} else {} end)'
