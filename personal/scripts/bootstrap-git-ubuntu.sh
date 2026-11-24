#!/usr/bin/env bash
# User-local Git + GitHub CLI from Ubuntu's authenticated apt metadata.
# No sudo, system package changes, credential changes or SSH forwarding.
set -euo pipefail
umask 077
base="$HOME/.local/share/cmux-personal/git-bootstrap"
mkdir -p "$base/packages" "$HOME/.local/bin"
cd "$base/packages"
apt download git gh libcurl3t64-gnutls liberror-perl
for package in ./*.deb; do dpkg-deb -x "$package" "$base/root"; done
if ! command -v git >/dev/null && [[ ! -e "$HOME/.local/bin/git" ]]; then
  cat > "$HOME/.local/bin/git" <<'WRAPPER'
#!/bin/sh
base="$HOME/.local/share/cmux-personal/git-bootstrap/root"
export GIT_EXEC_PATH="$base/usr/lib/git-core"
export GIT_TEMPLATE_DIR="$base/usr/share/git-core/templates"
export LD_LIBRARY_PATH="$base/usr/lib/$(uname -m)-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$base/usr/bin/git" "$@"
WRAPPER
  chmod 700 "$HOME/.local/bin/git"
fi
if ! command -v gh >/dev/null && [[ ! -e "$HOME/.local/bin/gh" ]]; then
  ln -s "$base/root/usr/bin/gh" "$HOME/.local/bin/gh"
fi
export PATH="$HOME/.local/bin:$PATH"
git --version
gh --version
# Verify the HTTPS helper can load, without contacting or signing in to a host.
if LD_LIBRARY_PATH="$base/root/usr/lib/$(uname -m)-linux-gnu" ldd "$base/root/usr/lib/git-core/git-remote-https" | grep -q 'not found'; then
  echo 'Git HTTPS dependencies are missing; inspect ldd output before cloning.' >&2
  exit 1
fi
