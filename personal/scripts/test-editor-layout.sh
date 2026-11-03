#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/cheatcode-editor-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx14.0" \
  "$root/Sources/PersonalChat/PersonalChatNativeTextView.swift" \
  "$root/personal/tests/EditorLayoutChecks.swift" -o "$work/check"
"$work/check"
