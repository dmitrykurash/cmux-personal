#!/usr/bin/env bash
# Optional user-local tmux for Ubuntu. apt verifies repository package hashes;
# this neither uses sudo nor changes system packages.
set -euo pipefail
umask 077
if command -v tmux >/dev/null || [[ -x "$HOME/.local/bin/tmux" ]]; then
  echo "tmux is already installed"
  exit 0
fi
base="$HOME/.local/share/cmux-personal/bootstrap"
mkdir -p "$base" "$HOME/.local/bin"
cd "$base"
apt download tmux libevent-core-2.1-7t64 libjemalloc2
for package in ./*.deb; do dpkg-deb -x "$package" root; done
cat > "$HOME/.local/bin/tmux" <<'SH'
#!/bin/sh
base="$HOME/.local/share/cmux-personal/bootstrap/root"
export LD_LIBRARY_PATH="$base/usr/lib/$(uname -m)-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$base/usr/bin/tmux" "$@"
SH
chmod 700 "$HOME/.local/bin/tmux"
"$HOME/.local/bin/tmux" -V
