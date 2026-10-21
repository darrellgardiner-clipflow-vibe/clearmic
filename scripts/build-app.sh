#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_args=(build -c release)
if [[ "${CLEARMIC_UNIVERSAL:-0}" == 1 ]]; then build_args+=(--arch arm64 --arch x86_64); fi
swift "${build_args[@]}"
bin_dir="$(swift "${build_args[@]}" --show-bin-path)"
app="$PWD/build/ClearMic.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin_dir/ClearMic" "$app/Contents/MacOS/ClearMic"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp .build/checkouts/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE"
cp vendor/RNNoise/NOTICE.txt "$app/Contents/Resources/RNNoise-LICENSE"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"
scripts/build-driver.sh
python3 scripts/package-component.py driver
cp build/ClearMic.icns "$app/Contents/Resources/"
python3 - "$app" <<'PY'
import json, os, pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
release = json.loads(pathlib.Path('Release/version.json').read_text())
info = {
    'CFBundleIdentifier': 'org.clearmic.app',
    'CFBundleExecutable': 'ClearMic', 'CFBundleName': 'ClearMic',
    'CFBundleIconFile': 'ClearMic.icns',
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
python3 scripts/sign-bundle.py "$app"
echo "Built $app"
