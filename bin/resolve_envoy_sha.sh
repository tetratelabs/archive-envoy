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
#   MAX_ENVOY_PUBLISH_AGE_SECONDS — maximum age of the successful run (default 7 days)

curlArgs=(
  -fsSL
  -H "Accept: application/vnd.github+json"
  -H "Cache-Control: no-cache"
  -H "X-GitHub-Api-Version: 2022-11-28"
)
if [ -n "${GH_TOKEN:-}" ]; then
  curlArgs+=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

# The workflow-runs endpoint can briefly serve a stale cached response while runs are
# completing. A unique query value and no-cache header keep concurrent nightly builds
# from resolving different commits.
requestId="$(date +%s)-$$"
latest_run=$(curl "${curlArgs[@]}" \
  "https://api.github.com/repos/envoyproxy/envoy/actions/workflows/envoy-publish.yml/runs?branch=main&status=success&per_page=10&request_id=${requestId}" |
  jq -cer '.workflow_runs | max_by([.created_at, .id])') || true

if [ -z "${latest_run}" ]; then
  echo >&2 "Could not resolve a successful Envoy publish workflow run"
  exit 1
fi

envoy_sha=$(echo "${latest_run}" | jq -r '.head_sha')
created_at=$(echo "${latest_run}" | jq -r '.created_at')

if ! [[ "${envoy_sha}" =~ ^[0-9a-f]{40}$ ]]; then
  echo >&2 "Could not resolve dev image SHA from Envoy publish workflow"
  exit 1
fi

max_age=${MAX_ENVOY_PUBLISH_AGE_SECONDS:-604800}
if ! [[ "${max_age}" =~ ^[0-9]+$ ]]; then
  echo >&2 "MAX_ENVOY_PUBLISH_AGE_SECONDS must be a non-negative integer"
  exit 1
fi

run_age=$(jq -nr --arg created_at "${created_at}" \
  'now - ($created_at | fromdateiso8601) | floor') || true
if ! [[ "${run_age}" =~ ^-?[0-9]+$ ]]; then
  echo >&2 "Could not determine the age of Envoy publish workflow run ${created_at}"
  exit 1
fi
if ((run_age > max_age)); then
  echo >&2 "Latest successful Envoy publish workflow run is ${run_age}s old; maximum is ${max_age}s"
  exit 1
fi

echo "${envoy_sha}"
