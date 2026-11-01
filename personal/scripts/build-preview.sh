#!/usr/bin/env bash
# Build the real native chat UI with Command Line Tools, without Ghostty/Xcode.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
dest="${1:?Pass an output directory}"
mkdir -p "$dest"
dest="$(cd "$dest" && pwd)"
app="$dest/CheatCode.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -swift-version 6 -target "$(uname -m)-apple-macosx14.0" \
  "$root"/Sources/PersonalChat/*.swift "$root/personal/PreviewMain.swift" \
  -o "$app/Contents/MacOS/PersonalChat"
cp "$root/personal/bridge.py" "$app/Contents/Resources/personal-bridge.py"
python3 - "$app/Contents/Resources/PersonalChatAssets" <<'PYLOGO'
from pathlib import Path
import sys
for name in ('axiom-symbol.svg', 'axiom-symbol.png'):
    (Path(sys.argv[1])/name).unlink(missing_ok=True)
PYLOGO
ditto "$root/personal/Assets" "$app/Contents/Resources/PersonalChatAssets"
cp "$root/personal/Assets/PersonalAppIcon.icns" "$app/Contents/Resources/PersonalAppIcon.icns"
python3 - "$root/Resources/Localizable.xcstrings" "$app/Contents/Resources" <<'PY'
import json
from pathlib import Path
import sys
catalog = json.loads(Path(sys.argv[1]).read_text())["strings"]
locales = {}
for key, entry in catalog.items():
    if not key.startswith("personal."):
        continue
    for locale, translation in entry.get("localizations", {}).items():
        if locale != "en":
            continue
        value = translation.get("stringUnit", {}).get("value")
        if value is not None:
            locales.setdefault(locale, []).append(json.dumps(key, ensure_ascii=False) + " = " + json.dumps(value, ensure_ascii=False) + ";")
for locale, lines in locales.items():
    folder = Path(sys.argv[2]) / (locale + ".lproj")
    folder.mkdir(exist_ok=True)
    (folder / "Localizable.strings").write_text("\n".join(lines) + "\n")
PY
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleIconFile</key><string>PersonalAppIcon</string>
<key>CFBundleExecutable</key><string>PersonalChat</string>
<key>CFBundleIdentifier</key><string>com.cmuxterm.app.debug.personal-preview</string>
<key>CFBundleName</key><string>CheatCode</string>
<key>CFBundleDisplayName</key><string>CheatCode</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>6</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -n "${CMUX_PERSONAL_PREVIEW_BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $CMUX_PERSONAL_PREVIEW_BUNDLE_ID" "$app/Contents/Info.plist"
fi
codesign --force --sign - "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$dest/CheatCode-macos.zip"
echo "Preview built in $dest"
