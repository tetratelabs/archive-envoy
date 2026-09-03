#!/usr/bin/env bash

# Copyright Archive Envoy
# SPDX-License-Identifier: Apache-2.0
# The full text of the Apache license is available in the LICENSE file at
# the root of the repo.

set -ueo pipefail

case "${NIGHTLY_VERSION:-}" in
dev) compilation_mode=opt ;;
dev_debug) compilation_mode=dbg ;;
*) echo >&2 "NIGHTLY_VERSION must be dev or dev_debug"; exit 1 ;;
esac

ref=${REQUESTED_ENVOY_SHA:-}
if [ -z "${ref}" ]; then
  ref=$("$(dirname "$0")/resolve_envoy_sha.sh")
elif ! [[ "${ref}" =~ ^[0-9a-f]{40}$ ]]; then
  echo >&2 "REQUESTED_ENVOY_SHA must be a 40-character lowercase hexadecimal SHA"
  exit 1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  output=${GITHUB_OUTPUT}
else
  output=/dev/stdout
fi

printf 'ref=%s\ncompilation_mode=%s\n' "${ref}" "${compilation_mode}" >> "${output}"
