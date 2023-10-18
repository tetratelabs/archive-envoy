#!/usr/bin/env bash

set -uex

downloadBaseURL="${1?-downloadBaseURL required ex https://archive.tetratelabs.io/envoy}"
bin/consolidate_release_versions.sh tetratelabs/archive-envoy "${downloadBaseURL}" 0 >public/envoy-versions.json
bin/consolidate_release_versions.sh tetratelabs/archive-envoy "${downloadBaseURL}" 1 >public/envoy-versions_debug.json
