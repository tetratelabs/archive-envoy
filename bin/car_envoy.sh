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
list) car="car -t --platform ${platform}" ;;
extract)
  [ "${os}" = 'windows' ] && directory=${directory}/bin
  car="car -x --platform ${platform} -C ${directory}"
  ;;
*) echo >&2 "invalid mode ${mode}" && exit 1 ;;
esac

# Validate we have a version for the given platform. This is similarly inconsistent at the moment.
case ${os} in
darwin) # https://github.com/Homebrew/homebrew-core/blob/master/Formula/envoy.rb
  # strip the v off the tag name more shell portable than ${version:1}
  v=$(echo "${version}" | cut -c2-100)

  # When a new minor version is released, you will have to make an '@' version for the previous minor.
  # Otherwise, you won't see new patches. Ex https://github.com/Homebrew/homebrew-core/blob/master/Formula/envoy@1.17.rb

  # You can check here in case a version was re-released
  # curl -fsSL -H 'Authorization: Bearer QQ==' 'https://ghcr.io/v2/homebrew/core/envoy/tags/list?n=10
  # curl -fsSL -H 'Authorization: Bearer QQ==' 'https://ghcr.io/v2/homebrew/core/envoy/1.17/tags/list?n=10
  case ${v} in
  1.18.3)
    reference=ghcr.io/homebrew/core/envoy:1.18.3-1
    ${car} --strip-components 2 -qf "${reference}" envoy/${v}/bin/envoy
    ;;
  1.17.*)
    reference=ghcr.io/homebrew/core/envoy/1.17:${v}
    ${car} --strip-components 3 -qf "${reference}" 'envoy@1.17'/${v}/bin/envoy
    ;;
  *) # current version
    reference=ghcr.io/homebrew/core/envoy:${v}
    ${car} --strip-components 2 -qf "${reference}" envoy/${v}/bin/envoy
    ;;
  esac
  ;;
linux)
  files="usr/local/bin/envoy"
  if [ "${debug:-}" = '1' ]; then
    reference=envoyproxy/envoy-debug:$(echo "${version}" | sed 's/_debug//g')
    files="$files usr/local/bin/envoy.dwp"
  else
    reference=envoyproxy/envoy:${version}
  fi

  ${car} --created-by-pattern 'ADD linux' --strip-components 2 -qf "${reference}" ${files}
  ;;
windows)
  reference=envoyproxy/envoy-windows:${version}
  ${car} --created-by-pattern ADD --strip-components 3 -qf "${reference}" 'Files/Program Files/envoy/envoy.exe'
  ;;
*)
  echo >&2 "os ${os} not yet supported" && exit 1
  ;;
esac
