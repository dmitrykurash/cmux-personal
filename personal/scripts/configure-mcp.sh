#!/usr/bin/env bash
# Run on the VPS as developer. Registers official endpoints, without secrets.
# Sign in through /mcp inside the interactive Claude terminal afterwards.
set -euo pipefail
claude_bin="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
if [[ "$(id -un)" != developer ]]; then echo "Run as developer" >&2; exit 1; fi
if ! "$claude_bin" mcp get krea >/dev/null 2>&1; then
  "$claude_bin" mcp add --scope user --transport http krea https://api.krea.ai/mcp
fi
if ! "$claude_bin" mcp get elevenlabs >/dev/null 2>&1; then
  "$claude_bin" mcp add --scope user --transport http elevenlabs https://api.elevenlabs.io/v1/mcp
fi
echo "Registered. Complete each provider's sign-in using /mcp in Claude Code."
