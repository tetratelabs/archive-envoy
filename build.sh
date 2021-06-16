#!/bin/sh -uex
baseURL="${1?-baseURL required ex https://archive.tetratelabs.io/envoy}"
ENVOY_VERSIONS_URL="${DEPLOY_PRIME_URL?-required ex http://localhost:8888}/envoy-versions.json"

# Ensure we have tools we need installed
export PATH=bin:$PATH
getenvoy -v >/dev/null 2>&1 || curl -sSL https://getenvoy.io/install.sh | sh -s

consolidate_release_versions.sh tetratelabs/archive-envoy "${baseURL}" > public/envoy-versions.json

# test getenvoy with the generated version list
export ENVOY_VERSIONS_URL
getenvoy versions -a
getenvoy run --version
