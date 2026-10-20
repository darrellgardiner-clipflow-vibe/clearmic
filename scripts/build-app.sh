#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app="$PWD/build/ClearMic.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin_dir/ClearMic" "$app/Contents/MacOS/ClearMic"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp vendor/RNNoise/NOTICE.txt "$app/Contents/Resources/RNNoise-LICENSE"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"
scripts/build-driver.sh
python3 scripts/package-component.py driver
python3 - "$app" <<'PY'
import json, os, pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
release = json.loads(pathlib.Path('Release/version.json').read_text())
info = {
    'CFBundleIdentifier': 'org.clearmic.app',
    'CFBundleExecutable': 'ClearMic', 'CFBundleName': 'ClearMic',
    'CFBundlePackageType': 'APPL', 'CFBundleVersion': os.environ.get('CLEARMIC_BUILD', release['build']),
    'CFBundleShortVersionString': os.environ.get('CLEARMIC_VERSION', release['version']),
    'LSMinimumSystemVersion': '14.0', 'NSPrincipalClass': 'NSApplication',
    'NSMicrophoneUsageDescription': 'ClearMic processes your selected microphone locally for recording and calls.',
    'SUFeedURL': 'https://raw.githubusercontent.com/darrellgardiner-clipflow-vibe/clearmic/main/Release/appcast.xml',
    'SUPublicEDKey': pathlib.Path('Release/public-key.txt').read_text().strip(),
    'SUEnableAutomaticChecks': True,
    'SUAutomaticallyUpdate': False,
    'SUVerifyUpdateBeforeExtraction': True,
    'SUEnableSystemProfiling': False,
}
with (app / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)
PY
codesign --force --sign "${CLEARMIC_SIGN_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
echo "Built $app"
