# Archive of Envoy® release binaries
As of June 2021, Envoy binaries are available in different places under different retention policies, or without a
policy. This repository's releases archive Envoy binaries so that they can have permalinks.

Specifically, these are tarballs with exactly the same binary as what users would have, if they used Docker or Homebrew
instructions from here: https://www.envoyproxy.io/docs/envoy/latest/start/install

## Release artifacts
Each release includes `envoy-$version-$os-$arch.tar.xz` for every platform, including a production, non-debug, binary.

Here are a couple examples:
 * `envoy-v1.18.3-linux-amd64.xz` contains only `envoy-v1.18.3-linux-amd64/bin/envoy`
 * `envoy-v1.18.3-windows-amd64.tar.xz` contains only `envoy-v1.18.3-windows-amd64/bin/envoy.exe`

It also includes `envoy-$version.json` which adheres to the [release versions schema](https://archive.tetratelabs.io/release-versions-schema.json).

## Archiving a release
Archiving a version means running [archive_release_version.sh](bin/archive_release_version.sh) for the version you want.

This happens automatically in [GitHub Actions](.github/workflows/release.yaml) a git tag push (ex. v1.18.3)

Ex. You can also run manually like this:
```bash
# optionally check first
export GITHUB_REPOSITORY=your_account/your_repo
./bin/archive_release_version.sh envoyproxy/envoy v1.18.3 check
./bin/archive_release_version.sh envoyproxy/envoy v1.18.3
```

## Regenerating the release versions list
https://archive.tetratelabs.io/envoy/envoy-versions.json is created automatically on master push, but you can also
trigger it on-demand via `netlify deploy`.

The [Netlify build](build.sh) generates `public/envoy-versions.json` instead of checking this into git. This simplifies
maintenance and also allows preview deploys to verify its contents.

If you want to run the build manually, you can.
```bash
# in one window
netlify dev
netlify build
open http://localhost:8888/envoy-versions.json
```

## Archive Rationale
Here are some examples of why stable archives help:
* Envoy "release" build in Azure Pipelines uploads releases as zip files
    * https://dev.azure.com/cncf/envoy/_build
    * These weren't designed for stable use, rather build stages.
    * The retention policy is 365 days
    * Access to builds sometimes disappears for other reasons
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
