#!/usr/bin/env bash

# Copyright Archive Envoy
# SPDX-License-Identifier: Apache-2.0
# The full text of the Apache license is available in the LICENSE file at
# the root of the repo.

set -ueo pipefail

cleanup_root=${MACOS_CLEANUP_ROOT:-}
if [ -n "${cleanup_root}" ]; then
  test_tmp_root=${TMPDIR:-/tmp}
  test_tmp_root=${test_tmp_root%/}
  case "${cleanup_root}" in
  "${test_tmp_root}"/archive-envoy-cleanup.*) ;;
  *) echo >&2 "MACOS_CLEANUP_ROOT must be an archive-envoy-cleanup test fixture"; exit 1 ;;
  esac
  active_developer_dir=${MACOS_ACTIVE_DEVELOPER_DIR:-}
  remove=(rm -rf --)
else
  if [ "$(uname -s)" != Darwin ]; then
    echo >&2 "macOS runner cleanup can only run on Darwin"
    exit 1
  fi
  active_developer_dir=$(xcode-select -p)
  remove=(sudo rm -rf --)
fi

active_xcode=${active_developer_dir%/Contents/Developer}
case "${active_xcode}" in
"${cleanup_root}"/Applications/Xcode*.app) ;;
*) echo >&2 "Active developer directory is not inside an Xcode application: ${active_developer_dir}"; exit 1 ;;
esac

remove_path() {
  local path=$1

  case "${path}" in
  "${cleanup_root}"/Applications/Xcode*.app | \
    "${active_xcode}"/Contents/Developer/Platforms/*.platform | \
    "${cleanup_root}"/Library/Developer/CoreSimulator/Profiles/Runtimes/*.simruntime) ;;
  *) echo >&2 "Refusing to remove unexpected path: ${path}"; exit 1 ;;
  esac

  echo "Removing ${path}"
  "${remove[@]}" "${path}"
}

echo "Disk space before cleanup:"
df -h "${cleanup_root:-/}"

for xcode in "${cleanup_root}"/Applications/Xcode*.app; do
  [ -d "${xcode}" ] || continue
  [ -L "${xcode}" ] && continue
  [ "${xcode}" = "${active_xcode}" ] && continue
  remove_path "${xcode}"
done

for platform in "${active_xcode}"/Contents/Developer/Platforms/*.platform; do
  [ -d "${platform}" ] || continue
  [ "$(basename "${platform}")" = MacOSX.platform ] && continue
  remove_path "${platform}"
done

for runtime in "${cleanup_root}"/Library/Developer/CoreSimulator/Profiles/Runtimes/*.simruntime; do
  [ -d "${runtime}" ] || continue
  remove_path "${runtime}"
done

echo "Disk space after cleanup:"
df -h "${cleanup_root:-/}"
