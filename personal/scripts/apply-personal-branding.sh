#!/usr/bin/env bash
# Apply the personal icon to the full fork's build checkout, including its
# runtime light/dark Dock images. Does not alter an installed application.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$root" <<'PY'
from pathlib import Path
import json, shutil, subprocess, sys
root = Path(sys.argv[1])
source = root/'personal/Assets/PersonalAppIcon.png'
for name in ['AppIcon', 'AppIcon-Debug']:
    folder = root/'Assets.xcassets'/(name+'.appiconset')
    for item in json.loads((folder/'Contents.json').read_text())['images']:
        pixels = int(item['size'].split('x')[0]) * int(item['scale'].removesuffix('x'))
        subprocess.run(['sips','-z',str(pixels),str(pixels),str(source),'--out',str(folder/item['filename'])],check=True,stdout=subprocess.DEVNULL)
for name in ['AppIconLight','AppIconDark']:
    shutil.copyfile(source, root/'Assets.xcassets'/(name+'.imageset')/(name+'.png'))
PY
