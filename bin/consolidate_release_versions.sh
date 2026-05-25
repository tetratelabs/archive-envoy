#!/usr/bin/env bash

# Copyright Archive Envoy
# SPDX-License-Identifier: Apache-2.0
# The full text of the Apache license is available in the LICENSE file at
# the root of the repo.

set -ue

# This creates a json file including all archived releases of a GitHub Repository.
# Notably, this rewrites tarball URLs as permalinks.
#
# Release metadata (releaseDate, commitSha) is read from each release's
# description field, and sha256sums from asset digests. No per-version JSON
# downloads are needed.

curl --version >/dev/null
jq --version >/dev/null
curl="curl -fsSL"

githubToken=${GITHUB_TOKEN:-}
if [ -z "${githubToken}" ] && [ -z "${RELEASES_JSON:-}" ]; then
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

releasesJson=${RELEASES_JSON:-}
if [ -n "${releasesJson}" ]; then
  allReleases=$(cat "${releasesJson}")
else
  # Fetch all releases with assets and digests via GraphQL (100 per page).
  graphqlQuery='query($owner:String!,$name:String!,$cursor:String){repository(owner:$owner,name:$name){releases(first:100,orderBy:{field:CREATED_AT,direction:DESC},after:$cursor){pageInfo{hasNextPage endCursor}nodes{tagName isDraft isPrerelease description releaseAssets(first:10){nodes{name digest downloadUrl}}}}}}'

  allReleases="[]"
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

    allReleases=$(echo "${allReleases}" "${response}" | jq -s '
      .[0] + [.[1].data.repository.releases.nodes[]
        | select((.isDraft == false and .isPrerelease == false)
              or .tagName == "dev" or .tagName == "dev_debug")]')

    hasNextPage=$(echo "${response}" | jq -r '.data.repository.releases.pageInfo.hasNextPage')
    [ "${hasNextPage}" = "true" ] || break
    cursor=$(echo "${response}" | jq '.data.repository.releases.pageInfo.endCursor')
  done
fi

# Transform GraphQL data into the consolidated release-versions JSON.
echo "${allReleases}" | jq \
  --arg debugVersion "${debugVersion}" \
  --arg redirectsTo "${redirectsTo}" \
  --arg downloadBaseURL "${downloadBaseURL}" \
'
# Filter by debug flag
[ .[] |
  (.tagName | test("_debug$")) as $isDebug |
  (.tagName == "dev_debug") as $isDevDebug |
  ($isDebug or $isDevDebug) as $isAnyDebug |
  select(
    if $debugVersion == "1" then $isAnyDebug
    else ($isAnyDebug | not)
    end
  )
] |

# Build versions, sha256sums, and dev from release data
reduce .[] as $r ({versions: {}, sha256sums: {}};
  $r.tagName as $tag |
  ($r.description // "") as $desc |

  # Parse envoy_release_date= from description
  (if $desc | test("envoy_release_date=") then $desc | capture("envoy_release_date=(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})") | .d else null end) as $date |

  # Tarball assets only
  [$r.releaseAssets.nodes[] | select(.name | endswith(".tar.xz"))] as $tarballs |

  # Build tarballs map: "os/arch" -> rewritten URL
  ($tarballs | reduce .[] as $a ({};
    ($a.name | ltrimstr("envoy-" + $tag + "-") | rtrimstr(".tar.xz") | split("-") | .[0] + "/" + .[1]) as $platform |
    ($a.downloadUrl | sub($redirectsTo; $downloadBaseURL)) as $url |
    . + {($platform): $url}
  )) as $tarballMap |

  # Build sha256sums from digests
  ($tarballs | reduce .[] as $a ({};
    if $a.digest != null and ($a.digest | startswith("sha256:")) then
      . + {($a.name): ($a.digest | ltrimstr("sha256:"))}
    else . end
  )) as $sums |

  if ($tag == "dev" or $tag == "dev_debug") then
    # Dev builds go under .dev with commitSha
    (if $desc | test("envoy_sha=") then $desc | capture("envoy_sha=(?<s>[0-9a-f]{40})") | .s else null end) as $commitSha |
    .dev = (
      {releaseDate: $date, tarballs: $tarballMap}
      + if $commitSha then {commitSha: $commitSha} else {} end
    ) |
    .sha256sums += $sums
  else
    # Regular versions go under .versions[key]
    ($tag | ltrimstr("v")) as $versionKey |
    .versions[$versionKey] = {releaseDate: $date, tarballs: $tarballMap} |
    .sha256sums += $sums
  end
) |

# Calculate latestVersion
.latestVersion = (
  .versions | keys |
  sort_by(gsub("_debug$";"") | split(".") | map(tonumber)) |
  last
) |

# Select output keys in schema order
{latestVersion, versions, sha256sums} + (if .dev then {dev} else {} end)
'
