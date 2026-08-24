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

## Why is the Go cache keyed by `bin/car_envoy.sh`?

The archive script invokes `car` with `go run` at a revision pinned in
`bin/car_envoy.sh`. This repository is not otherwise a Go module, so it has no
`go.mod` for `actions/setup-go` to use as its default cache dependency file.

[`cache-dependency-path`][setup-go-cache] accepts any file whose contents
represent the cached inputs. Hashing `bin/car_envoy.sh` preserves caching for
the Go module and build caches, invalidates them when the pinned `car` revision
changes, and avoids adding a module manifest solely for one build tool.

## Why does auto-release check Docker Hub before triggering?

Envoy's Docker images appear on Docker Hub 3-6 hours after the GitHub release
tag is created. The release workflow pulls binaries from
`envoyproxy/envoy:vX.Y.Z`, so triggering before the image exists fails the
job. Rather than add retry logic to the release workflow, the auto-release
script checks the Docker Hub registry API and skips versions whose images are
not ready. The 6-hour cron interval means those versions get picked up on the
next run.

## Why does auto-release fetch 10 releases?

Envoy has never published more than 6 [releases][envoy-releases] in a single
day. Fetching 10 gives margin while keeping Docker Hub checks to only what is
actually new.

---
[envoy-releases]: https://github.com/envoyproxy/envoy/blob/main/RELEASES.md
[envoy-publish]: https://github.com/envoyproxy/envoy/blob/main/.github/workflows/envoy-publish.yml
[dockerhub-dev]: https://hub.docker.com/r/envoyproxy/envoy/tags?name=dev-
[dockerhub-debug-dev]: https://hub.docker.com/r/envoyproxy/envoy/tags?name=debug-dev-
[setup-go-cache]: https://github.com/actions/setup-go/blob/main/docs/advanced-usage.md#multi-target-builds
