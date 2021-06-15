# Archive of Envoy® release binaries
As of June 2021, Envoy binaries are available in different places under different retention policies, or without a
policy. This script helps you create an archive of Envoy binaries so that you can still use it later.

The tool creates a tarball with exactly the same binary as what users would have, if they used Docker or Homebrew
instructions from here: https://www.envoyproxy.io/docs/envoy/latest/start/install

## Archive format
This archives `$version/envoy-$version-$os-$arch.tar.xz` for every platform, including a production, non-debug, binary.

Here are a couple examples:
 * `v1.18.3/envoy-v1.18.3-linux-amd64.xz` contains only `envoy-v1.18.3-linux-amd64/bin/envoy`
 * `v1.18.3/envoy-v1.18.3-windows-amd64.tar.xz` contains only `envoy-v1.18.3-windows-amd64/bin/envoy.exe`

This also creates [`$version/envoy-$version.json`](https://getenvoy.io/envoy-versions-schema.json) with sha256sums.

## Archiving a release
Archiving a version means running [archive_envoy_release.sh](archive_envoy_release.sh) for the version you want.

Ex.
```bash
# optionally check first
export GITHUB_REPOSITORY=your_account/your_repo
./archive_envoy_release v1.18.3 check
./archive_envoy_release v1.18.3
```

## Rationale
Here are some examples of why stable archives are needed:
* Envoy "release" build in Azure Pipelines uploads releases as zip files
    * https://dev.azure.com/cncf/envoy/_build
    * These weren't designed for stable use, rather build stages.
    * The retention policy is 365 days
* Envoy "official" tarballs aren't currently implemented
    * https://github.com/envoyproxy/envoy/issues/16830 will eventually define stable tars
    * Which version+os+arch dimensions to publish, and the retention policy are yet unknown
* Envoy Docker images exist, but are neither official nor from a verified publisher.
    * https://hub.docker.com/r/envoyproxy/envoy
    * https://hub.docker.com/r/envoyproxy/envoy-windows
    * Under DockerHub retention policy, these delete if not pulled within 6 months
* Envoy MacOS binaries exist in Homebrew
    * https://github.com/Homebrew/homebrew-core/blob/master/Formula/envoy.rb
    * Only a few versions exist as of 2021-06, and HomeBrew policy is max 5 versions.

## Notes about artifacts published by Azure Pipelines

First, find the `${buildId}` by doing a search link this and clicking on the result. The `buildId` query parameter of the web page is the `${BUILD_ID}`
Ex. For v1.18.3 https://dev.azure.com/cncf/envoy/_build?view=runs&keywordFilter=v1.18.3

Now, navigate to the published artifacts: `https://dev.azure.com/cncf/envoy/_build/results?view=artifacts&pathAsName=false&type=publishedArtifacts&buildId=${buildId}`
Ex. For v1.18.3 https://dev.azure.com/cncf/envoy/_build/results?view=artifacts&pathAsName=false&type=publishedArtifacts&buildId=75331

Here is a description of the `${artifactName}` you will use later, specifically only release ones. These are in zip format, this describes what's in them.

* `bazel.release`, `bazel.release.arm64`
    * These are for `linux/amd64` and `linux/arm64` docker platforms
    * includes `bazel.release/envoy_binary.tar.gz` which includes
        * `build_release/envoy.dwp`, `build_release/envoy` - larger debug (dbg) builds of envoy
        * `build_release/su-exec`
            * Dockerfile doesn't set a non-root user. Instead, it switches to non-root at runtime while retaining pid 1
        * build_release_stripped/envoy which is what docker runs
* `windows.release` (aka windows/amd64)
    * This is for the `windows/amd64` docker platforms
    * includes `windows.release/source/exe/envoy.exe` which is what Docker uses
    * includes `windows.release/envoy_binary.tar.gz` which includes the above

Hover your mouse the `${artifactId}` you want and a kebab menu (3 vertical dots) gives the option to "Copy download URL".
You'll notice the following template: `https://dev.azure.com/cncf/4684fb3d-0389-4e0b-8251-221942316e06/_apis/build/builds/${buildId}/artifacts?api-version=6.0&$format=zip&artifactName=${artifactName}`
Ex. For v1.18.3 `windows.release` https://dev.azure.com/cncf/4684fb3d-0389-4e0b-8251-221942316e06/_apis/build/builds/75331/artifacts?api-version=6.0&$format=zip&artifactName=windows.release

Note, unlike the search or artifacts URL, the download URL requires no authentication. Also, the `$format` or `%24format` is a real query parameter name!

-----
Envoy® is a registered trademark of The Linux Foundation in the United States and/or other countries
