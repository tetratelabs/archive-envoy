# Archive of Envoy® release binaries
As of June 2021, Envoy binaries are available in different places under different retention policies, or without a
policy. This repository's releases archive Envoy binaries so that they can have permalinks.

The archived releases have permalinks in [envoy-versions.json](https://archive.tetratelabs.io/envoy/envoy-versions.json),
which adheres to the [release versions schema](https://archive.tetratelabs.io/release-versions-schema.json).

Specifically, releases include a tarball per platform with exactly the same binary as what users would have, if
they used Docker or Homebrew instructions from here: https://www.envoyproxy.io/docs/envoy/latest/start/install

## Standard releases
A standard release includes `envoy-$version-$os-$arch.tar.xz` for every platform, including a production, non_debug,
binary.

Here are a couple examples:
 * `envoy-v1.18.3-linux-amd64.xz` contains `envoy-v1.18.3-linux-amd64/bin/envoy`

It also includes `envoy-$version.json` which adheres to the [release versions schema](https://archive.tetratelabs.io/release-versions-schema.json).

### Debug releases
Debug versions help provide troubleshooting information to Envoy maintainers when there is a crash (Segmentation fault).
A debug version ends in `_debug` (ex `v1.18.3_debug`) and listed in [envoy-versions_debug.json](https://archive.tetratelabs.io/envoy/envoy-versions_debug.json).

*NOTE* Debug builds are very large. For example, the normal build may be less than 70MB, while its debug build is >2GB.
Only use debug versions in advanced situations.

The main visible change is insight into the source that led to a segmentation fault.

Ex. a normal version may crash with a backtrace like this:
```
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:104] Caught Segmentation fault, suspect faulting address 0x0
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:91] Backtrace (use tools/stack_decode.py to get line numbers):
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:92] Envoy version: d362e791eb9e4efa8d87f6d878740e72dc8330ac/1.18.2/Clean/RELEASE/BoringSSL
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:96] #0: __restore_rt [0x7f75e06d1980]
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:98] #1: [0x55974d40da69]
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:98] #2: [0x55974daae313]
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:98] #3: [0x55974cf2d94d]
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:98] #4: [0x55974cf316d5]
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:98] #5: [0x55974cf3fd41]
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:98] #6: [0x55974d02e2e0]
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:98] #7: [0x55974d036a36]
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:98] #8: [0x55974ce066bf]
[2021-06-18 03:51:22.264][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:98] #9: [0x55974cf65f40]
[2021-06-18 03:51:22.265][33][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:98] #10: [0x55974cf66382]
```

A debug version has more information in the backtrace, and may lead to faster diagnosis: 
```
[2021-06-18 03:44:43.425][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:104] Caught Segmentation fault, suspect faulting address 0x0
[2021-06-18 03:44:43.425][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:91] Backtrace (use tools/stack_decode.py to get line numbers):
[2021-06-18 03:44:43.425][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:92] Envoy version: d362e791eb9e4efa8d87f6d878740e72dc8330ac/1.18.2/Clean/RELEASE/BoringSSL
[2021-06-18 03:44:43.425][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:96] #0: __restore_rt [0x7f93cafa5980]
[2021-06-18 03:44:43.432][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:98] #1: [0x55e14b315a69]
[2021-06-18 03:44:43.432][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:96] #2: std::__terminate() [0x55e14b9b6313]
[2021-06-18 03:44:43.432][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:96] #3: Envoy::Http::ConnectionManagerImpl::ActiveStream::chargeStats() [0x55e14ae3594d]
[2021-06-18 03:44:43.432][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:96] #4: Envoy::Http::ConnectionManagerImpl::ActiveStream::encodeHeaders() [0x55e14ae396d5]
[2021-06-18 03:44:43.432][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:96] #5: Envoy::Http::FilterManager::encodeHeaders() [0x55e14ae47d41]
[2021-06-18 03:44:43.432][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:96] #6: Envoy::Router::Filter::onUpstreamHeaders() [0x55e14af362e0]
[2021-06-18 03:44:43.432][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:96] #7: Envoy::Router::UpstreamRequest::decodeHeaders() [0x55e14af3ea36]
[2021-06-18 03:44:43.432][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:96] #8: Envoy::Http::Http1::ActiveClient::StreamWrapper::decodeHeaders() [0x55e14ad0e6bf]
[2021-06-18 03:44:43.432][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:96] #9: Envoy::Http::Http1::ClientConnectionImpl::onHeadersCompleteBase() [0x55e14ae6df40]
[2021-06-18 03:44:43.432][32][critical][backtrace] [bazel-out/k8-opt/bin/source/server/_virtual_includes/backtrace_lib/server/backtrace.h:96] #10: Envoy::Http::Http1::ClientConnectionImpl::onHeadersCompleteBase() [0x55e14ae6e382]
```

## Archiving a release
Archiving a version means running [archive_release_version.sh](bin/archive_release_version.sh) for the version you want.

This happens automatically in the [release workflow](https://github.com/tetratelabs/archive-envoy/actions/workflows/release.yaml)
when given a valid version parameter (ex v1.18.3 or v1.18.3_debug).

Ex. You can also run manually like this:
```bash
# optionally check first
./bin/archive_release_version.sh envoyproxy/envoy v1.18.3 check
./bin/archive_release_version.sh envoyproxy/envoy v1.18.3
```

## Regenerating the release versions list
https://archive.tetratelabs.io/envoy/envoy-versions.json is created automatically on a release tag or on master push.
You can also trigger it on-demand via `netlify deploy`.

The [Netlify build](build.sh) generates `public/envoy-versions.json` and `public/envoy-versions_debug.json` instead of
checking this into git. This simplifies maintenance and also allows preview deploys to verify its contents.

If you want to run the build manually, you can.
```bash
# in one window
npm install --save-dev netlify-cli
./node_modules/.bin/netlify dev
./node_modules/.bin/netlify build
open http://localhost:8888/envoy-versions.json
open http://localhost:8888/envoy-versions_debug.json
```

## Archive Rationale
Here are some examples of why stable archives help:
* Most release sources don't have permalinks
    * In the past tarballs hosted on Bintray, which is being turned down, invalidating links.
* Envoy "release" build in Azure Pipelines uploads releases as zip files
    * https://dev.azure.com/cncf/envoy/_build
    * These weren't designed for stable use, rather build stages.
    * The retention policy is 365 days
    * Access to builds sometimes disappear for other reasons
* Envoy "official" tarballs aren't currently implemented
    * https://github.com/envoyproxy/envoy/issues/16830 will eventually define stable tars
    * Which version+os+arch dimensions to publish, and the retention policy are yet unknown
* Envoy Docker images exist, but are neither official nor from a verified publisher.
    * https://hub.docker.com/r/envoyproxy/envoy
    * Under DockerHub retention policy, these delete if not pulled within 6 months
* Envoy MacOS binaries exist in Homebrew
    * https://github.com/Homebrew/homebrew-core/blob/master/Formula/envoy.rb
    * Only a few versions exist as of 2021-06, and HomeBrew policy is max 5 versions.

-----
Envoy® is a registered trademark of The Linux Foundation in the United States and/or other countries
