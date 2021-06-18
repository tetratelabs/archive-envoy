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

# This creates a directory archiving a GitHub release version for all available platforms.
#  * The first parameter ($1) is the source GitHub repository to archive. Ex envoyproxy/envoy
#  * The second parameter ($2) is the version. Ex "v1.18.3" or "v1.18.3_debug"
#  * The third parameter ($3) is optional, either "archive" (default) or "check"
#
# The result is a directory $2 which includes all release artifacts that should be published.
# Notably, these are tarballs and a release version list in JSON format. Platforms which fail for
# any reason are not included in the JSON list.
#
# IMPORTANT: "_debug" is not used when looking up the release https://github.com/$1/releases/tag/$2
# Ex. If $1=envoyproxy/envoy $2=v1.18.3_debug, the source release is...
# https://github.com/envoyproxy/envoy/releases/tag/v1.18.3 not
# https://github.com/envoyproxy/envoy/releases/tag/v1.18.3_debut not
#
# The "_debug" suffix is only used to allow the tar script to separate debug files from production.
#
# This runs a tar script for each OS and architecture to create $name-$version-$os-$arch.tar.xz
# The tar script name includes the basename of $1. If $1=envoyproxy/envoy: tar_envoy_artifact.sh
# The arguments passed to the tar script are: $version $os $arch $op
# This resulting tarball must include at least a working binary. Failures are ignored
#
# Notes:
#  * The resulting tarball is "tar.xz" not "tar.gz" as the former is significantly smaller.

# Verify args
sourceGitHubRepository=${1?sourceGitHubRepository is required. ex envoyproxy/envoy}
name=$(basename "${sourceGitHubRepository}") || exit 1
case "${2:-}" in
v[0-9]*[0-9]_debug)
  version=$2
  sourceVersion=$(echo "${2}" | sed 's/_debug//g')
  ;;
v[0-9]*[0-9])
  version=$2
  sourceVersion=$2
  ;;
*) echo >&2 "version is required. Ex v1.18.3 or v1.18.3_debug" && exit 1 ;;
esac
op=${3:-archive}

archiveBaseUrl="https://github.com/${GITHUB_REPOSITORY:-tetratelabs/archive-envoy}/releases/download/${version}"

# Ensure we have tools we need installed
curl --version >/dev/null
sha256sum --version >/dev/null
jq --version >/dev/null

tarScript="$(dirname "$0")/tar_${name}_artifact.sh"
if [ ! -x "${tarScript}" ]; then
   echo >&2 "tarScript ${tarScript} must be executable" && exit 1
fi

# Setup defaults that make archival consistent between runs
export TZ=UTC
# ex. "2021-05-11T19:15:27Z" ->  "2021-05-11"
RELEASE_DATE=$(curl -sSL "https://api.github.com/repos/${sourceGitHubRepository}/releases"'?per_page=100' |
  jq -er ".|map(select(.prerelease == false and .draft == false and .name ==\"${sourceVersion}\"))|first|.published_at" | cut -c1-10) || exit 1
export RELEASE_DATE

echo "archiving ${sourceGitHubRepository} ${version} released on ${RELEASE_DATE}"
# archive all dists for the version, generating https://archive.tetratelabs.io/release-versions-schema.json incrementally
releaseVersions="{}"
for os in darwin linux windows; do
  for arch in amd64 arm64; do
    # permit a version to fail rather than duplicating maintenance here and in archive_release.sh
    set +e
    "${tarScript}" "${version}" "${os}" "${arch}" "${op}"
    rc=$?
    set -e
    [ "${op}" = 'check' ] || [ "${rc}" != '0' ] && continue

    f="${name}-${version}-${os}-${arch}.tar.xz"
    s=$(sha256sum "${version}/${f}" | awk '{print $1}') || exit 1
    # strip the v off the tag name more shell portable than ${version:1}
    v=$(echo "${version}" | cut -c2-100)
    # use printf because jq doesn't support parameterizing the key names, only the key values
    nextReleaseVersion=$(printf '{"latestVersion": "%s", "versions": { "%s": {"releaseDate": "%s", "tarballs": {"%s": "%s"}}}, "sha256sums": {"%s": "%s"}}' \
      "$v" "$v" "${RELEASE_DATE}" "${os}/${arch}" "${archiveBaseUrl}/${f}" "${f}" "$s")
    # merge the pending releaseVersions json to include the next dist
    releaseVersions=$(echo "${releaseVersions}" "${nextReleaseVersion}" | jq -Sse '.[0] * .[1]')
  done
done

[ "${op}" = 'check' ] && exit 0
[ "${releaseVersions}" = '{}' ] && exit 1

# reorder top-level keys so that versions appear before sha256sums
releaseVersions=$(echo "${releaseVersions}" | jq '{latestVersion: .latestVersion, versions: .versions, sha256sums: .sha256sums}')
# Write the versions file and reset file date as if they were published at the same time
echo "${releaseVersions}" >"${version}/${name}-${version}.json"
find "${version}" -exec touch -t "${RELEASE_DATE}" {} \;
