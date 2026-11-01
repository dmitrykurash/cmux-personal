#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/cmux-startup-checks.XXXXXX")"
trap 'rm -f "$work/check"; rmdir "$work"' EXIT
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx14.0" \
  "$root"/Sources/PersonalChat/*.swift "$root/personal/tests/StartupChecks.swift" -o "$work/check"
"$work/check"
