#!/usr/bin/env bash
# Opt-in macOS 26 integration check. May download Apple's English/Russian models.
# Synthesizes a known phrase locally; never records the microphone.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/cheatcode-speech-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT
/usr/bin/say -v Samantha -o "$work/fixture.aiff" 'Keep this message in the draft. Review the words before sending.'
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx26.0" \
  "$root"/Sources/PersonalChat/PersonalChatSpeechServing.swift \
  "$root"/Sources/PersonalChat/PersonalChatSpeechError.swift \
  "$root"/Sources/PersonalChat/PersonalChatSpeechPipeline.swift \
  "$root"/Sources/PersonalChat/PersonalChatSpeechAudioConverter.swift \
  "$root"/Sources/PersonalChat/PersonalChatStrings.swift \
  "$root"/personal/tests/SpeechEngineChecks.swift -o "$work/check"
"$work/check" "$work/fixture.aiff"
/usr/bin/say -v Milena -o "$work/russian.aiff" 'Сохрани это сообщение в черновике. Проверь текст перед отправкой.'
"$work/check" "$work/russian.aiff" ru-RU
