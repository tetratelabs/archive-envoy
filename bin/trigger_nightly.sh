#!/usr/bin/env bash

# Copyright Archive Envoy
# SPDX-License-Identifier: Apache-2.0
# The full text of the Apache license is available in the LICENSE file at
# the root of the repo.

set -ueo pipefail

envoy_sha=${ENVOY_SHA:-}
if [ -z "${envoy_sha}" ]; then
  envoy_sha=$("$(dirname "$0")/resolve_envoy_sha.sh")
elif ! [[ "${envoy_sha}" =~ ^[0-9a-f]{40}$ ]]; then
  echo >&2 "ENVOY_SHA must be a 40-character lowercase hexadecimal SHA"
  exit 1
fi

gh workflow run nightly.yaml -f version=dev -f envoy_sha="${envoy_sha}"
gh workflow run nightly.yaml -f version=dev_debug -f envoy_sha="${envoy_sha}"
