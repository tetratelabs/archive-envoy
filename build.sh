#!/bin/sh -uex
downloadBaseURL="${1?-downloadBaseURL required ex https://archive.tetratelabs.io/envoy}"
bin/consolidate_release_versions.sh tetratelabs/archive-envoy "${downloadBaseURL}" >public/envoy-versions.json
