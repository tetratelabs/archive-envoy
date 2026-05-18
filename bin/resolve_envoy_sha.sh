#!/usr/bin/env bash

# Copyright Archive Envoy
# SPDX-License-Identifier: Apache-2.0
# The full text of the Apache license is available in the LICENSE file at
# the root of the repo.

set -ueo pipefail

# Resolves the commit SHA from Envoy's last successful "Publish & verify" workflow run on main.
# Don't use Docker Hub's tag listing API — its ordering reflects vulnerability rescans, not push time.
# https://github.com/envoyproxy/envoy/blob/main/.github/workflows/envoy-publish.yml
#
# Outputs the 40-char SHA to stdout. Exits non-zero if it cannot be resolved.
#
# Optional environment:
#   GH_TOKEN — GitHub token for authenticated API requests (avoids rate limiting)

curl="curl -fsSL"
authHeader=""
if [ -n "${GH_TOKEN:-}" ]; then
  authHeader="Authorization: Bearer ${GH_TOKEN}"
fi

envoy_sha=$(${curl} ${authHeader:+ -H "${authHeader}"} \
  "https://api.github.com/repos/envoyproxy/envoy/actions/workflows/envoy-publish.yml/runs?branch=main&status=success&per_page=1" |
  jq -r '.workflow_runs[0].head_sha')

if [ -z "${envoy_sha}" ] || [ "${envoy_sha}" = "null" ]; then
  echo >&2 "Could not resolve dev image SHA from Envoy publish workflow"
  exit 1
fi

echo "${envoy_sha}"
