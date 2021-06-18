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

# This creates a directory archiving an Envoy® release in tar.xz format.
#  * The first parameter ($1) is the release version. Ex. v1.18.3 or v1.18.3_debug.
#    * The "_debug" suffix toggles if the binary is stripped or not, and if debug symbols are included.
#  * The second parameter ($2) is the operating system: darwin, linux or windows
#  * The third parameter ($3) is the architecture: amd64 or arm64
#  * The fourth parameter ($4) is optional, either "archive" (default) or "check"
#    * Check exits successfully if the download URL or Docker image are available.
#
# The result is a file envoy-$version-$os-$arch.tar.xz which contents appropriate per platform
#  Ex. envoy-v1.18.3-linux-amd64.xz contains envoy-v1.18.3-linux-amd64/bin/envoy
#  Ex. envoy-v1.18.3-windows-amd64.tar.xz contains envoy-v1.18.3-windows-amd64/bin/envoy.exe
#
# Notes:
#  * The resulting tarball is "tar.xz" not "tar.gz" as the former is significantly less storage and bandwidth.
#  * If an Azure Pipeline build is known it is used, otherwise Docker is.
#  * Darwin is a special-case and extracted from HomeBrew
#  * This script may be simplified when  https://github.com/envoyproxy/envoy/issues/16830 completes
#
# -----
# Envoy® is a registered trademark of The Linux Foundation in the United States and/or other countries

# Ensure we have tools we need installed
curl --version >/dev/null
tar=tar
docker --version >/dev/null
# we need GNU tar. On Darwin, the system default is not gtar. `brew install gtar` if that's you!
which gtar >/dev/null && tar=gtar
${tar} --version | grep 'GNU tar' >/dev/null

# Verify args
version=${1?version is required. Ex v1.18.3 or v1.18.3_debug}
os=${2?os is required. Ex darwin linux or windows}
arch=${3:-amd64}
op=${4:-archive}

case ${op} in
archive | check) ;;
*) echo >&2 "os ${os} invalid operation: valid choices are archive and check" && exit 1 ;;
esac

case ${os} in
darwin | linux | windows) ;;
*) echo >&2 "os ${os} unsupported: valid choices are darwin, linux or windows" && exit 1 ;;
esac

case ${arch} in
amd64 | arm64) ;;
*) echo >&2 "arch ${arch} unsupported: valid choices are amd64 or arm64" && exit 1 ;;
esac

not_yet_arch() {
  echo >&2 "arch ${arch} not yet supported on ${os}" && exit 1
}

not_yet_version() {
  echo >&2 "version ${version} not yet supported on ${os}-${arch}" && exit 1
}

case ${version} in v[0-9]*[0-9]_debug) debug="1" ;; esac

curl="curl -fsSL"
untargz="${tar} --no-same-owner -xpzf"

# Setup defaults that make archival consistent between runs
export TZ=UTC
tarxz="${tar} --numeric-owner --owner 65534 --group 65534 --mtime ${RELEASE_DATE?-ex. 2021-05-11} -cpJf"

# Validate we have a version for the given platform. This is similarly inconsistent at the moment.
case ${os} in
darwin)
  if [ "$arch" != 'amd64' ]; then not_yet_arch; fi # https://github.com/envoyproxy/envoy/issues/16482
  case ${version} in
  # Verify the version and use sha256 for big_sur https://github.com/Homebrew/homebrew-core/blob/master/Formula/envoy.rb
  v1.18.3) homebrewSha=d03fb86b48336c8d3c0f3711cfc3df3557f9fb33c966ceb1caecae1653935e90 ;;
  *) not_yet_version ;; # versions before 1.18.3 are massive so created manually
  esac
  # If this drifts, run `brew reinstall envoy -d` and see what the URL pattern is
  downloadURL=https://ghcr.io/v2/homebrew/core/envoy/blobs/sha256:${homebrewSha}
  curl="${curl} --oauth2-bearer QQ=="
  ;;
linux | windows)
  # Search on https://dev.azure.com/cncf/envoy/_build?view=runs&keywordFilter=${version} and click the result
  # The `buildId` is the query parameter of the resulting web page
  case ${version} in
  v1.18.3 | v1.18.3_debug) buildId=75331 ;;
  v1.18.2) ;; # buildId=72198 publishedArtifacts aren't visible
  v1.18.1) not_yet_version ;; # buildId=72179 publishedArtifacts aren't visible and no docker image!
  v1.18.0) not_yet_version ;; # buildId=72169 publishedArtifacts aren't visible and no docker image!
  v1.17.3 | v1.17.3_debug) buildId=75332 ;;
  v1.17.2) ;; # buildId=72166 publishedArtifacts aren't visible
  v1.17.1) ;; # buildId=67489 publishedArtifacts aren't visible
  v1.16.4 | v1.16.4_debug) buildId=75333 ;;
  v1.16.3) ;; # buildId=72165 publishedArtifacts aren't visible; requested tetratelabs/getenvoy#274
  v1.16.2) ;; # buildId=60159 publishedArtifacts aren't visible
  v1.15.5 | v1.15.5_debug) buildId=75334 ;;
  v1.15.4 | v1.15.4_debug) buildId=72164 ;;
  v1.15.3) ;; # buildId=60136 publishedArtifacts aren't visible
  v1.14.7) ;; # buildId=72163 publishedArtifacts aren't visible
  v1.14.6) ;; # buildId=60135 publishedArtifacts aren't visible
  v1.14.0) not_yet_version ;; # buildId=unknown and no docker image!
  v1.13.5) not_yet_version ;; # buildId=52493 publishedArtifacts aren't visible and no docker image!
  v1.13.8) not_yet_version ;; # buildId=64171 publishedArtifacts aren't visible and no docker image!
  *) ;; # versions before 1.14 publishedArtifacts aren't visible
  esac

  if [ "${os}" = 'linux' ]; then
    if [ "${version}" = 'v1.18.1' ]; then
      not_yet_version # buildId=72179 published windows artifacts, but no docker image!
    elif [ "${arch}" = 'amd64' ]; then
      artifactName=bazel.release
    else
      artifactName=bazel.release.arm64
      case ${version} in
      v1.15.[45]) artifactName=bazel.release.server_only.arm64 ;; # handle special-case
      v1.1[2345]*) not_yet_arch ;;
      esac
    fi

    if [ "${buildId:-}" = '' ]; then
      # Fall back to Docker as Linux has these for a long time.
      if [ "${debug:-}" = '' ]; then
        dockerImage=envoyproxy/envoy:${version}
      else
        dockerImage=envoyproxy/envoy-debug:$(echo "${version}" | sed 's/_debug//g')
      fi
    fi
  else # Windows was added in 1.16
    artifactName=windows.release
    [ "${debug:-}" != '' ] && not_yet_version # windows.release doesn't include debug symbols
    case ${version} in v1.1[2345]*) not_yet_version ;; esac
    [ "$arch" != 'amd64' ] && not_yet_arch     # No one raised an issue in Envoy, yet.
    [ "${buildId:-}" = '' ] && not_yet_version # We can't fall back to Docker on Windows
  fi

  # If this drifts, look at the published artifacts (you need to log in, but no access otherwise).
  # https://dev.azure.com/cncf/envoy/_build/results?view=artifacts&pathAsName=false&type=publishedArtifacts&buildId=${buildId}
  # Then, hover your mouse the `${artifactId}` you want and a kebab menu (3 vertical dots) shows "Copy download URL".
  if [ "${buildId:-}" != '' ]; then
    downloadURL="https://dev.azure.com/cncf/4684fb3d-0389-4e0b-8251-221942316e06/_apis/build/builds/${buildId}/artifacts?api-version=6.0&%24format=zip&artifactName=${artifactName}"
  fi
  ;;
esac

dist="envoy-${version}-${os}-${arch}"
echo "using ${dist}"
if [ "${dockerImage:-}" != '' ]; then
  echo "pulling dockerImage ${dockerImage}"
  docker pull --platform "${os}/${arch}" "${dockerImage}" >/dev/null || exit 1
  [ "${op}" = 'check' ] && exit 0
else
  echo "checking downloadURL ${downloadURL}"
  if [ "${artifactName:-}" != '' ]; then # Azure Pipelines doesn't support HTTP HEAD
    jsonURL=$(echo "${downloadURL}" | sed 's/format=zip/format=json/g')
    ${curl} "${jsonURL}" >/dev/null || exit 1
  else
    ${curl} --head "${downloadURL}" >/dev/null || exit 1
  fi
  [ "${op}" = 'check' ] && exit 0
  echo "downloading ${downloadURL}"
fi

# Now everything is ok, write the source
mkdir -p "${version}/${dist}/bin"
cd "${version}"
if [ "${dockerImage:-}" != '' ]; then
  # docker run -ti --rm --entrypoint /bin/sh --platform "${os}/${arch}" ${dockerImage} to debug if necessary
  containerid=$(docker create --platform "${os}/${arch}" "${dockerImage}") || exit 1
  sources="/usr/local/bin/envoy /usr/local/bin/su-exec"
  [ "${debug:-}" != '' ] && sources="${sources} /usr/local/bin/envoy.dwp"
  for source in ${sources}; do
    file=$(basename "${source}")
    docker cp "$containerid:${source}" "${dist}/bin/${file}"
    if [ ! -f "${dist}/bin/${file}" ]; then
      echo >&2 "file ${source} missing from platform ${os}/${arch} of ${dockerImage}" && exit 1
    fi
  done
  docker rm "$containerid"
elif [ "${os}" = 'darwin' ]; then # get it from homebrew
  # strip the v off the tag name more shell portable than ${version:1}
  v=$(echo "${version}" | cut -c2-100)
  binDir="envoy/${v}/bin"
  ${curl} "${downloadURL}" | ${untargz} - "${binDir}"
  cp -p "${binDir}/envoy" "${dist}/bin/"
  rm -rf envoy
else # get it from Envoy's Azure Pipeline published artifacts.
  zip="${dist}.zip"
  ${curl} "${downloadURL}" >"${zip}"
  unzip -qq -o "${zip}" && rm "${zip}"
  if [ "${os}" = 'linux' ]; then
    if [ "${debug:-}" = '' ]; then
      sources="build_release_stripped/envoy build_release/su-exec"
    else
      sources="build_release/envoy build_release/envoy.dwp build_release/su-exec"
    fi

    # shellcheck disable=SC2086
    (cd "${artifactName}" && ${untargz} envoy_binary.tar.gz ${sources})

    for source in ${sources}; do
      file=$(basename "${source}")
      cp -p "${artifactName}/${source}" "${dist}/bin/${file}"

      if [ ! -f "${dist}/bin/${file}" ]; then
        echo >&2 "file ${source} missing from envoy_binary.tar.gz in ${downloadURL}" && exit 1
      fi
    done
  else # windows
    source="source/exe/envoy.exe"
    file=$(basename "${source}")
    cp -p "${artifactName}/${source}" "${dist}/bin/${file}"

    if [ ! -f "${dist}/bin/${file}" ]; then
      echo >&2 "file ${source} missing from ${downloadURL}" && exit 1
    fi
  fi
  rm -rf "${artifactName}"
fi

archive="${dist}.tar.xz"
echo "archiving ${archive}"
${tarxz} "${archive}" "${dist}/"
rm -rf "${dist}"
