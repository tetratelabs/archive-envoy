#!/usr/bin/env bash

# Copyright Archive Envoy
# SPDX-License-Identifier: Apache-2.0
# The full text of the Apache license is available in the LICENSE file at
# the root of the repo.

set -ueo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cleanup_script="${repo_root}/bin/cleanup_macos_runner.sh"
test_tmp_root=${TMPDIR:-/tmp}
test_tmp_root=${test_tmp_root%/}
fixture_root=$(mktemp -d "${test_tmp_root}/archive-envoy-cleanup.XXXXXX")

cleanup_fixture() {
  case "${fixture_root}" in
  "${test_tmp_root}"/archive-envoy-cleanup.*) rm -rf -- "${fixture_root}" ;;
  *) echo >&2 "Refusing to remove unexpected test fixture: ${fixture_root}"; exit 1 ;;
  esac
}
trap cleanup_fixture EXIT

active_xcode="${fixture_root}/Applications/Xcode_16.4.app"
unused_xcode="${fixture_root}/Applications/Xcode_26.3.app"
active_platforms="${active_xcode}/Contents/Developer/Platforms"
runtimes="${fixture_root}/Library/Developer/CoreSimulator/Profiles/Runtimes"

mkdir -p \
  "${active_platforms}/MacOSX.platform" \
  "${active_platforms}/iPhoneOS.platform" \
  "${unused_xcode}" \
  "${runtimes}/iOS.simruntime"
ln -s Xcode_16.4.app "${fixture_root}/Applications/Xcode.app"

MACOS_CLEANUP_ROOT=${fixture_root} \
MACOS_ACTIVE_DEVELOPER_DIR="${active_xcode}/Contents/Developer" \
  "${cleanup_script}" >/dev/null

[ -d "${active_xcode}" ] || { echo >&2 "active Xcode was removed"; exit 1; }
[ -d "${active_platforms}/MacOSX.platform" ] || { echo >&2 "macOS platform was removed"; exit 1; }
[ -L "${fixture_root}/Applications/Xcode.app" ] || { echo >&2 "active Xcode symlink was removed"; exit 1; }
[ ! -e "${unused_xcode}" ] || { echo >&2 "unused Xcode was not removed"; exit 1; }
[ ! -e "${active_platforms}/iPhoneOS.platform" ] || { echo >&2 "unused platform was not removed"; exit 1; }
[ ! -e "${runtimes}/iOS.simruntime" ] || { echo >&2 "simulator runtime was not removed"; exit 1; }

if MACOS_CLEANUP_ROOT=/ \
  MACOS_ACTIVE_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  "${cleanup_script}" >/dev/null 2>&1; then
  echo >&2 "unsafe cleanup root was accepted"
  exit 1
fi

echo "PASS: macOS runner cleanup"
