#!/usr/bin/env bash

# Copyright Archive Envoy
# SPDX-License-Identifier: Apache-2.0
# The full text of the Apache license is available in the LICENSE file at
# the root of the repo.

set -ueo pipefail

# This creates a directory archiving a GitHub release version for all available platforms.
#  * The first parameter ($1) is the source GitHub repository to archive. Ex envoyproxy/envoy
#  * The second parameter ($2) is the version. Ex "v1.18.3" or "v1.18.3_debug"
#  * The third parameter ($3) is optional, either "archive" (default) or "check"
#
# The result is a directory $2 which includes all release artifacts that should be published.
# Notably, these are tarballs and a release version list in JSON format. Platforms which fail for
# any reason are not included in the JSON list.
#
# IMPORTANT: "_debug" is not used when looking up the source release.
# Ex. If $1=envoyproxy/envoy $2=v1.18.3_debug, the source release is...
# https://github.com/envoyproxy/envoy/releases/tag/v1.18.3
#
# The "_debug" suffix is only used to allow the car script to separate debug files from production.
#
# This runs a car script for each OS and architecture to create $name-$version-$os-$arch.tar.xz
# The car script name includes the basename of $1. If $1=envoyproxy/envoy: car_envoy.sh
# The arguments passed to the car script are: $version $sourceVersion $os $arch $op $directory
# This resulting tarball must include at least a working binary. Failures are ignored
#
# Notes:
#  * The resulting tarball is "tar.xz" not "tar.gz" as the former is significantly smaller.

# Verify args
sourceGitHubRepository=${1?sourceGitHubRepository is required. ex envoyproxy/envoy}
name=$(basename "${sourceGitHubRepository}") || exit 1
case "${2:-}" in
dev|dev_debug)
  [ -z "${ENVOY_SHA:-}" ] && echo >&2 "ENVOY_SHA required for dev builds" && exit 1
  version=$2
  sourceVersion=${version%_debug}
  ;;
v[0-9]*[0-9]_debug|v[0-9]*[0-9])
  version=$2
  sourceVersion=${version%_debug}
  ;;
*) echo >&2 "version is required. Ex v1.18.3 or v1.18.3_debug" && exit 1 ;;
esac
op=${3:-archive}

archiveBaseUrl="https://github.com/${GITHUB_REPOSITORY:-tetratelabs/archive-envoy}/releases/download/${version}"

# Ensure we have tools we need installed
curl --version >/dev/null
sha256sum --version >/dev/null
jq --version >/dev/null
tar=tar
# we need GNU tar. On Darwin, the system default is not gtar. `brew install gnu-tar` if that's you!
which gtar >/dev/null && tar=gtar
${tar} --version | grep 'GNU tar' >/dev/null

carScript="$(dirname "$0")/car_${name}.sh"
if [ ! -x "${carScript}" ]; then
  echo >&2 "car script ${carScript} must be executable" && exit 1
fi

case ${op} in
check) carMode=list ;;
archive) carMode=extract ;;
*) echo >&2 "invalid op ${op}" && exit 1 ;;
esac

curl="curl -fsSL"

# A valid GitHub token to avoid rate limiting. GH_TOKEN is also used by the gh CLI below;
# retain GITHUB_TOKEN as a compatibility fallback for local callers.
githubToken=${GH_TOKEN:-${GITHUB_TOKEN:-}}
# Prepare authorization header when performing request to api.github.com to avoid rate limiting, especially when testing locally.
authorizationHeader="Authorization: Bearer ${githubToken}"

# Setup defaults that make archival consistent between runs
export TZ=UTC

# Dev builds resolve the release date from the commit
if [ -n "${ENVOY_SHA:-}" ]; then
  envoy_sha=${ENVOY_SHA}
  RELEASE_DATE=$(${curl} ${githubToken:+ -H "${authorizationHeader}"} \
    "https://api.github.com/repos/${sourceGitHubRepository}/commits/${envoy_sha}" |
    jq -er '.commit.committer.date' | cut -c1-10) || exit 1
else

# Fetch the last page number of releases (example value: 7), so we can get all of the releases.
# To get the last page, we send a HEAD request to "https://api.github.com/repos/${sourceGitHubRepository}/releases",
# then "grep" the "link" header value.
# Reference: https://docs.github.com/en/rest/guides/using-pagination-in-the-rest-api?apiVersion=2022-11-28#using-link-headers.
lastReleasePage=$(${curl}I ${githubToken:+ -H "${authorizationHeader}"} "https://api.github.com/repos/${sourceGitHubRepository}/releases" |
  grep -Eo 'page=[0-9]+' | awk 'NR==2' | cut -d'=' -f2) || exit 1

RELEASE_DATE="null"
for ((page = 1; page <= lastReleasePage; page++)); do
  # ex. "2021-05-11T19:15:27Z" ->  "2021-05-11"
  RELEASE_DATE=$(${curl} ${githubToken:+ -H "${authorizationHeader}"} -fsSL "https://api.github.com/repos/${sourceGitHubRepository}/releases"'?page='"${page}" |
    jq -er ".|map(select(.prerelease == false and .draft == false and .name ==\"${sourceVersion}\"))|first|.published_at" | cut -c1-10) || exit 1
  if [ "${RELEASE_DATE}" != "null" ]; then
      break
  fi
done

if [ "${RELEASE_DATE}" = "null" ]; then
  echo >&2 "version ${sourceVersion} has not yet been released" && exit 1
fi

fi

export RELEASE_DATE
tarxz="${tar} --numeric-owner --owner 65534 --group 65534 --mtime ${RELEASE_DATE?-ex. 2021-05-11} -cpJf"

echo >&2 "archiving ${sourceGitHubRepository} ${version} released on ${RELEASE_DATE}"
# archive all dists for the version, generating https://archive.tetratelabs.io/release-versions-schema.json incrementally
releaseVersions="{}"
archiveRepo=${GITHUB_REPOSITORY:-tetratelabs/archive-envoy}

# ARCHIVE_OS filters to a single OS when set (used by split lanes).
archiveOS=${ARCHIVE_OS:-}

for os in darwin linux; do
  [ -n "${archiveOS}" ] && [ "${os}" != "${archiveOS}" ] && continue
  for arch in arm64 amd64; do
    [ "${os}" = 'darwin' ] && [ "${arch}" = 'amd64' ] && continue

    dist="envoy-${version}-${os}-${arch}"
    echo >&2 "using dist: ${dist}"

    if [ -d "${version}/${dist}" ]; then
      echo >&2 "using existing dist"
    else
      # permit a version to fail rather than duplicating maintenance here and in archive_release.sh
      set +e
      "${carScript}" "${version}" "${sourceVersion}" "${os}" "${arch}" "${carMode}" "${version}/${dist}"
      rc=$?
      set -e
      [ "${op}" = 'check' ] || [ "${rc}" != '0' ] && continue

      if ! [ -d "${version}/${dist}" ]; then
        echo >&2 "expected to extract files for ${os}/${arch}" && exit 1
      fi
    fi

    archive="${dist}.tar.xz"
    echo >&2 "creating ${archive}"
    (cd "${version}" && ${tarxz} "${archive}" "${dist}")
    rm -rf "${version}/${dist}"
    s=$(sha256sum "${version}/${archive}" | awk '{print $1}') || exit 1

    # use printf because jq doesn't support parameterizing the key names, only the key values
    case ${version} in
    dev|dev_debug)
      nextReleaseVersion=$(printf '{"dev": {"releaseDate": "%s", "commitSha": "%s", "tarballs": {"%s": "%s"}}, "sha256sums": {"%s": "%s"}}' \
        "${RELEASE_DATE}" "${envoy_sha}" "${os}/${arch}" "${archiveBaseUrl}/${archive}" "${archive}" "$s")
      ;;
    *)
      # strip the v off the tag name more shell portable than ${version:1}
      v=$(echo "${version}" | cut -c2-100)
      nextReleaseVersion=$(printf '{"latestVersion": "%s", "versions": { "%s": {"releaseDate": "%s", "tarballs": {"%s": "%s"}}}, "sha256sums": {"%s": "%s"}}' \
        "$v" "$v" "${RELEASE_DATE}" "${os}/${arch}" "${archiveBaseUrl}/${archive}" "${archive}" "$s")
      ;;
    esac
    # merge the pending releaseVersions json to include the next dist
    releaseVersions=$(echo "${releaseVersions}" "${nextReleaseVersion}" | jq -Sse '.[0] * .[1]')
  done
done

[ "${op}" = 'check' ] && exit 0
[ "${releaseVersions}" = '{}' ] && exit 1

# Seed from existing release JSON so split lanes merge into one file.
# Done after archiving so the second lane to finish picks up the first lane's results.
existing=$(gh release download "${version}" -R "${archiveRepo}" -p "${name}-${version}.json" -O - 2>/dev/null) || true
if [ -n "${existing}" ]; then
  releaseVersions=$(echo "${existing}" "${releaseVersions}" | jq -Sse '.[0] * .[1]')
fi

case ${version} in
dev|dev_debug)
  releaseVersions=$(echo "${releaseVersions}" | jq '{dev, sha256sums}')
  ;;
*)
  # reorder top-level keys so that versions appear before sha256sums
  releaseVersions=$(echo "${releaseVersions}" | jq '{latestVersion, versions, sha256sums}')
  ;;
esac
# Write the versions file and reset file date as if they were published at the same time
echo "${releaseVersions}" >"${version}/${name}-${version}.json"
touchDate=$(echo "${RELEASE_DATE}"|sed 's/-//g')0000
find "${version}" -exec touch -t "${touchDate}" {} \;

# Emit the release body to stdout for the caller to capture.
if [ -n "${envoy_sha:-}" ]; then
  echo "envoy_sha=${envoy_sha}"
fi
echo "envoy_release_date=${RELEASE_DATE}"
