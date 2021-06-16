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

# This creates a directory archiving an Envoy® release including all available platforms
#
# -----
# Envoy® is a registered trademark of The Linux Foundation in the United States and/or other countries

# Ensure we have tools we need installed
curl --version >/dev/null
sha256sum --version >/dev/null
jq --version >/dev/null

# Verify args
version=${1?version is required. Ex v1.18.3}
archiveBaseUrl="https://github.com/${GITHUB_REPOSITORY}/releases/download/$version"
op=${2:-archive}

# Setup defaults that make archival consistent between runs
export TZ=UTC
# ex. "2021-05-11T19:15:27Z" ->  "2021-05-11"
RELEASE_DATE=$(curl -sSL 'https://api.github.com/repos/envoyproxy/envoy/releases?per_page=100' |
  jq -er ".|map(select(.name ==\"$version\"))|first|.published_at" | cut -c1-10) || exit 1
export RELEASE_DATE

echo "archiving ${version} released on ${RELEASE_DATE}"
# archive all dists for the version, generating the envoy-versions.json format incrementally
envoyVersions="{}"
for os in darwin linux windows; do
  for arch in amd64 arm64; do

    # permit a version to fail rather than duplicating maintenance here and in archive_envoy.sh
    set +e
    ./archive_envoy.sh "${version}" "${os}" "${arch}" "${op}"
    rc=$?
    set -e
    [ "${op}" = 'check' ] || [ "${rc}" != '0' ] && continue

    f="envoy-${version}-${os}-${arch}.tar.xz"
    s=$(sha256sum "${version}/${f}" | awk '{print $1}') || exit 1
    # strip the v off the tag name more shell portable than ${version:1}
    v=$(echo "${version}" | cut -c2-100)
    # use printf because jq doesn't support parameterizing the key names, only the key values
    nextEnvoyVersion=$(printf '{"latestVersion": "%s", "versions": { "%s": {"releaseDate": "%s", "tarballs": {"%s": "%s"}}}, "sha256sums": {"%s": "%s"}}' \
      "$v" "$v" "${RELEASE_DATE}" "${os}/${arch}" "${archiveBaseUrl}/${f}" "${f}" "$s")
    # merge the pending envoyVersions json to include the next dist
    envoyVersions=$(echo "${envoyVersions}" "${nextEnvoyVersion}" | jq -Sse '.[0] * .[1]')
  done
done

[ "${op}" = 'check' ] && exit 0
[ "${envoyVersions}" = '{}' ] && exit 1

# reorder top-level keys so that versions appear before sha256sums
envoyVersions=$(echo "${envoyVersions}" | jq '{latestVersion: .latestVersion, versions: .versions, sha256sums: .sha256sums}')
# Write the versions file and reset file date as if they were published at the same time
echo "${envoyVersions}" >"${version}/envoy-${version}.json"
find "${version}" -exec touch -t "${RELEASE_DATE}" {} \;
