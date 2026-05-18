# Notable rationale of archive-envoy

## Why is macOS built from source?

Envoy publishes Docker images for Linux only. macOS binaries are built from
source by checking out envoyproxy/envoy and building with Bazel. Linux
tarballs are archived independently of the macOS build, so they still
publish when the macOS build fails.

For nightly builds, there is no release tag to check out. We resolve the
commit SHA from Envoy's last successful [Publish & verify][envoy-publish]
run, which is the commit whose images exist on [Docker Hub][dockerhub-dev].

## Why do we use a top-level "dev" key for nightly builds?

`dev` is not a semver version and carries `commitSha` instead of a version
number. Putting it inside `"versions"` would break existing consumers that
parse semver-keyed entries. A separate top-level `"dev"` key means consumers
are unaffected unless they opt in.

A single `dev` release overwrites daily, so there is only ever one dev build.
You cannot reinstall an older nightly or have parallel dev builds for different
branches. This keeps release count and maintenance bounded, and avoids
notifying repository watchers daily.


---
[envoy-publish]: https://github.com/envoyproxy/envoy/blob/main/.github/workflows/envoy-publish.yml
[dockerhub-dev]: https://hub.docker.com/r/envoyproxy/envoy/tags?name=dev-
[dockerhub-debug-dev]: https://hub.docker.com/r/envoyproxy/envoy/tags?name=debug-dev-
