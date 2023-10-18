#!/usr/bin/env bash -ue

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

# This is an Envoy® plug-in to extract_release_version.sh and called in a loop for each OS and
# architecture for a given version. The result is a distribution directory including the `envoy` binary.
#
#  * The first parameter ($1) is the release version. Ex. v1.18.3 or v1.18.3_debug.
#    * The "_debug" suffix toggles if the binary is stripped and if debug symbols are included.
#  * The second parameter ($2) is the operating system: darwin, linux or windows
#  * The third parameter ($3) is the architecture: amd64 or arm64
#  * The fourth parameter ($4) is the `car` mode: extract or list
#    * list exits successfully if the expected files are available in OCI layers
#  * The fifth parameter ($5) is the directory to extract files into
#
# The result is envoy-$version-$os-$arch which contents appropriate per platform
#  Ex. envoy-v1.18.3-linux-amd64/bin/envoy
#  Ex. envoy-v1.18.3-windows-amd64/bin/envoy.exe
#
# -----
# Envoy® is a registered trademark of The Linux Foundation in the United States and/or other countries

# Ensure we have tools we need installed
car >/dev/null
curl --version >/dev/null
jq --version >/dev/null
curl="curl -fsSL"

# Verify args
version=${1?version is required. Ex v1.18.3 or v1.18.3_debug}
os=${2?os is required: darwin linux or windows}
arch=${3?arch is required: amd64 or arm64}
mode=${4?mode is required: list or extract}
directory=${5:-}

platform=${os}/${arch}
case ${version} in v[0-9]*[0-9]_debug) debug="1" ;; esac

if [ "${debug:-}" = '1' ] && [ "${os}" != 'linux' ]; then
  echo >&2 "debug not yet supported on ${os}" && exit 1
fi

case ${mode} in
list) car="car --vv -t --platform ${platform}" ;;
extract)
  [ "${os}" = 'windows' ] && directory=${directory}/bin
  car="car -x --platform ${platform} -C ${directory}"
  ;;
*) echo >&2 "invalid mode ${mode}" && exit 1 ;;
esac

# Validate we have a version for the given platform. This is similarly inconsistent at the moment.
case ${os} in
darwin) # https://github.com/Homebrew/homebrew-core/blob/master/Formula/envoy.rb
  # -c2 will strip the v off the tag name more shell portable than ${version:1}
  minor_version=$(echo "${version}" | cut -c2-5)
  patch_version=$(echo "${version}" | cut -c2-100)

  # Homebrew's primary formula should be the stable release, but sometimes it
  # is behind. Once we understand this, we'll know if we should try a versioned
  # formula or not.
  if ! formula_json=$(${curl} https://formulae.brew.sh/api/formula/envoy.json 2>&-); then
    echo >&2 "Could not download the Homebrew formula JSON" && exit 1
  fi
  stable_patch_version=$(echo "${formula_json}" | jq -er .versions.stable)
  stable_minor_version=$(echo "${stable_patch_version}"| cut -c1-4)

  # Now, check to see if the version we want is the stable release. It could be
  # a versioned formula and that will have a different HTTP path including the
  # minor version.
  tags_url=https://ghcr.io/v2/homebrew/core/envoy/tags/list
  formula=envoy
  path=envoy
  if [ "${minor_version}" != "${stable_minor_version}" ]; then
    tags_url=$(echo ${tags_url}| sed "s~envoy~envoy/${minor_version}~")
    formula=envoy@${minor_version}
    path=envoy/${minor_version}
  fi

  # The tags for this formula could be mixed versions and also ambiguous. This
  # constrained to the patch we are looking for and also ensures we get the
  # last publication of it (ex 1.19.1-1 not 1.19.1).
  tag=""
  if tags_json=$(${curl} -H 'Authorization: Bearer QQ==' -H 'Accept: application/json' "${tags_url}" 2>&-); then
    tag=$(echo "${tags_json}"|jq -er '.tags |.[]' | sed -n "/${patch_version}/p"|sort -n|tail -1)
  fi
  if [ -z "${tag}" ]; then
    echo >&2 "version ${patch_version} is not available in Homebrew formula ${formula}" && exit 1
  fi

  ${car} --strip-components 2 -qf "ghcr.io/homebrew/core/${path}:${tag}" "${formula}/${patch_version}/bin/envoy"
  ;;
linux)
  files="usr/local/bin/envoy"
  if [ "${debug:-}" = '1' ]; then
    reference=envoyproxy/envoy-debug:$(echo "${version}" | sed 's/_debug//g')
    files="$files usr/local/bin/envoy.dwp"
  else
    reference=envoyproxy/envoy:${version}
  fi

  # Don't use --created-by-pattern because Envoy 1.22.0+ changed the image layer containing the binary.
  # Note: Unlike windows, layers preceding the Envoy binary are small, so scanning through is OK.
  ${car} --strip-components 2 -qf "${reference}" ${files}
  ;;
windows)
  reference=envoyproxy/envoy-windows:${version}
  ${car} --created-by-pattern ADD --strip-components 3 -qf "${reference}" 'Files/Program Files/envoy/envoy.exe'
  ;;
*)
  echo >&2 "os ${os} not yet supported" && exit 1
  ;;
esac
