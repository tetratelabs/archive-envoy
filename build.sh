#!/bin/sh -uex
downloadBaseURL="${1?-downloadBaseURL required ex https://archive.tetratelabs.io/envoy}"

bin/consolidate_release_versions.sh tetratelabs/archive-envoy "${downloadBaseURL}" >public/envoy-versions.json

testURL=${2:-}
[ "${testURL}" = '' ] && exit 0

# Ensure we have tools we need installed
export PATH=bin:$PATH
getenvoy -v >/dev/null 2>&1 || curl -sSL https://getenvoy.io/install.sh | sh -s

# test getenvoy with the generated version list
export ENVOY_VERSIONS_URL="${testURL}/envoy-versions.json"
getenvoy versions -a
getenvoy run --version
