#!/usr/bin/env bash
# Exercises the production callback on a foreign queue with synthetic samples.
# No device input, recording, model download or microphone permission required.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/cheatcode-microphone-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT
swiftc -O -swift-version 6 -target "$(uname -m)-apple-macosx26.0" \
  "$root"/Sources/PersonalChat/PersonalChatSpeechServing.swift \
  "$root"/Sources/PersonalChat/PersonalChatSpeechError.swift \
  "$root"/Sources/PersonalChat/PersonalChatSpeechMicrophone.swift \
  "$root"/Sources/PersonalChat/PersonalChatSpeechAudioConverter.swift \
  "$root"/Sources/PersonalChat/PersonalChatStrings.swift \
  "$root"/personal/tests/MicrophoneCallbackChecks.swift -o "$work/check"
"$work/check"
