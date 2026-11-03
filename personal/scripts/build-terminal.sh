#!/usr/bin/env bash
# Build the pinned native terminal library using Command Line Tools (no Xcode).
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
revision=464df5207fc2432e16c9a23abe538187196daf5f # SwiftTerm 1.19.0, Swift 6.0
cache="$root/.personal-deps/SwiftTerm-$revision"
if [[ ! -d "$cache/.git" ]]; then
  mkdir -p "$cache"
  git -C "$cache" init -q
  git -C "$cache" remote add origin https://github.com/migueldeicaza/SwiftTerm.git
  git -C "$cache" fetch --depth 1 origin "$revision"
  git -C "$cache" checkout --detach FETCH_HEAD
fi
[[ "$(git -C "$cache" rev-parse HEAD)" == "$revision" ]]
git -C "$cache" diff --exit-code --quiet
cp "$root/personal/SwiftTerm.resolved" "$cache/Package.resolved"
swift build --package-path "$cache" -c release --target SwiftTerm --force-resolved-versions
