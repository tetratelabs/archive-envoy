#!/usr/bin/env bash

# shellcheck disable=SC1090,SC2329

# Copyright Archive Envoy
# SPDX-License-Identifier: Apache-2.0
# The full text of the Apache license is available in the LICENSE file at
# the root of the repo.

set -ueo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
sha_resolver="${repo_root}/bin/resolve_envoy_sha.sh"
input_resolver="${repo_root}/bin/resolve_nightly_inputs.sh"
trigger="${repo_root}/bin/trigger_nightly.sh"

old_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
new_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
old_created_at=$(jq -nr 'now - 3600 | strftime("%Y-%m-%dT%H:%M:%SZ")')
new_created_at=$(jq -nr 'now | strftime("%Y-%m-%dT%H:%M:%SZ")')
stale_created_at=$(jq -nr 'now - 604801 | strftime("%Y-%m-%dT%H:%M:%SZ")')

fail() {
  echo >&2 "FAIL: $*"
  exit 1
}

assert_equal() {
  local expected=$1
  local actual=$2
  local message=$3
  [ "${actual}" = "${expected}" ] ||
    fail "${message}: expected '${expected}', got '${actual}'"
}

run_sha_resolver() {
  local response=$1

  (
    curl() {
      case " $* " in
      *" Cache-Control: no-cache "*) ;;
      *) return 1 ;;
      esac
      case " $* " in
      *" X-GitHub-Api-Version: 2022-11-28 "*) ;;
      *) return 1 ;;
      esac
      case " $* " in
      *"request_id="*) ;;
      *) return 1 ;;
      esac
      printf '%s\n' "${response}"
    }

    source "${sha_resolver}"
  )
}

response=$(printf '%s' \
  '{"workflow_runs":[' \
  "{\"id\":1,\"created_at\":\"${old_created_at}\",\"head_sha\":\"${old_sha}\"}," \
  "{\"id\":2,\"created_at\":\"${new_created_at}\",\"head_sha\":\"${new_sha}\"}" \
  ']}')
actual=$(run_sha_resolver "${response}")
assert_equal "${new_sha}" "${actual}" "resolver should select the newest successful run"

if run_sha_resolver '{"workflow_runs":[]}' >/dev/null 2>&1; then
  fail "resolver should reject an empty workflow response"
fi

if run_sha_resolver \
  "{\"workflow_runs\":[{\"id\":1,\"created_at\":\"${new_created_at}\",\"head_sha\":\"invalid\"}]}" \
  >/dev/null 2>&1; then
  fail "resolver should reject a malformed SHA"
fi

if run_sha_resolver \
  "{\"workflow_runs\":[{\"id\":1,\"created_at\":\"${stale_created_at}\",\"head_sha\":\"${new_sha}\"}]}" \
  >/dev/null 2>&1; then
  fail "resolver should reject a stale successful run"
fi

actual=$(NIGHTLY_VERSION=dev REQUESTED_ENVOY_SHA="${new_sha}" "${input_resolver}")
assert_equal "ref=${new_sha}
compilation_mode=opt" "${actual}" "normal inputs should select opt mode"

actual=$(NIGHTLY_VERSION=dev_debug REQUESTED_ENVOY_SHA="${new_sha}" "${input_resolver}")
assert_equal "ref=${new_sha}
compilation_mode=dbg" "${actual}" "debug inputs should select dbg mode"

if NIGHTLY_VERSION=invalid REQUESTED_ENVOY_SHA="${new_sha}" "${input_resolver}" \
  >/dev/null 2>&1; then
  fail "input resolver should reject an invalid version"
fi

if NIGHTLY_VERSION=dev REQUESTED_ENVOY_SHA=invalid "${input_resolver}" \
  >/dev/null 2>&1; then
  fail "input resolver should reject a malformed requested SHA"
fi

dispatches=$(
  (
    gh() {
      printf '%s\n' "$*"
    }

    ENVOY_SHA=${new_sha}
    export ENVOY_SHA
    source "${trigger}"
  )
)
assert_equal "workflow run nightly.yaml -f version=dev -f envoy_sha=${new_sha}
workflow run nightly.yaml -f version=dev_debug -f envoy_sha=${new_sha}" \
  "${dispatches}" "trigger should dispatch both variants with one SHA"

if (
  gh() { :; }
  ENVOY_SHA=invalid
  export ENVOY_SHA
  source "${trigger}"
) >/dev/null 2>&1; then
  fail "trigger should reject a malformed SHA"
fi

echo "PASS: nightly workflow scripts"
