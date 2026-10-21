#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="$PWD/build/ClearMic.driver"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
xcrun clang -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -O2 -Wno-format-extra-args -bundle \
  -include "$PWD/Driver/ClearMicConfig.h" vendor/BlackHole/BlackHole.c \
  -framework CoreAudio -framework CoreFoundation -framework Accelerate \
  -o "$bundle/Contents/MacOS/ClearMic"
swift scripts/build-icon.swift build/ClearMic.iconset
iconutil -c icns build/ClearMic.iconset -o build/ClearMic.icns
cp build/ClearMic.icns "$bundle/Contents/Resources/"
# Remove the old branded resource from incremental build output only.
python3 - "$bundle" <<'CLEAN'
import pathlib, sys
(pathlib.Path(sys.argv[1]) / 'Contents/Resources/BlackHole.icns').unlink(missing_ok=True)
CLEAN
cp LICENSE "$bundle/Contents/Resources/LICENSE"
python3 - "$bundle" <<'PY'
import pathlib, plistlib, sys
bundle = pathlib.Path(sys.argv[1])
factory = '62E3CF98-69B3-49FB-9B91-F4B67A178705'
info = {
    'CFBundleIdentifier': 'org.clearmic.audio.driver',
    'CFBundleExecutable': 'ClearMic', 'CFBundleName': 'ClearMic',
    'CFBundlePackageType': 'BNDL', 'CFBundleVersion': '1',
    'CFBundleShortVersionString': '0.1.0',
    'CFPlugInFactories': {factory: 'BlackHole_Create'},
    'CFPlugInTypes': {'443ABAB8-E7B3-491A-B985-BEB9187030DB': [factory]},
}
with (bundle / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)
PY
python3 scripts/sign-bundle.py "$bundle"
echo "Built $bundle"
