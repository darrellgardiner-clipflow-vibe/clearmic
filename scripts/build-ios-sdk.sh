#!/bin/bash
# Cross-compile the real app without signing or requiring an installed simulator runtime.
set -euo pipefail
cd "$(dirname "$0")/.."
for ios_sdk in iphoneos iphonesimulator; do
    ios_sdk_path="$(xcrun --sdk "$ios_sdk" --show-sdk-path)"
    ios_target=arm64-apple-ios17.0
    [[ "$ios_sdk" != iphonesimulator ]] || ios_target=arm64-apple-ios17.0-simulator
    ios_output="$PWD/build/ios-sdk/$ios_sdk"
    ios_app="$ios_output/ClearMic.app"
    mkdir -p "$ios_app"
    xcrun --sdk "$ios_sdk" swiftc -sdk "$ios_sdk_path" -target "$ios_target" -swift-version 5 \
        -parse-as-library -emit-module -emit-object -module-name RouteCore \
        ios/RouteCore/Sources/RouteCore/MicrophoneSession.swift \
        -emit-module-path "$ios_output/RouteCore.swiftmodule" -o "$ios_output/RouteCore.o"
    xcrun --sdk "$ios_sdk" swiftc -sdk "$ios_sdk_path" -target "$ios_target" -swift-version 5 \
        -parse-as-library -I "$ios_output" "$ios_output/RouteCore.o" ios/App/*.swift \
        -o "$ios_app/ClearMic"
    python3 - "$ios_app" "$ios_sdk" <<'PY'
import json, pathlib, plistlib, subprocess, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads(pathlib.Path('ios/App/Info.plist').read_bytes())
info.update(CFBundleDevelopmentRegion='en', CFBundleExecutable='ClearMic',
            CFBundleIdentifier=json.loads(pathlib.Path('ios/Release.json').read_text())['bundleId'], CFBundleName='ClearMic',
            CFBundleShortVersionString=json.loads(pathlib.Path('ios/Release.json').read_text())['version'],
            CFBundleVersion=subprocess.check_output(['git', 'rev-list', '--count', 'HEAD'], text=True).strip(),
            MinimumOSVersion='17.0', UIDeviceFamily=[1, 2],
            CFBundleSupportedPlatforms=['iPhoneOS' if sys.argv[2] == 'iphoneos' else 'iPhoneSimulator'])
(app / 'Info.plist').write_bytes(plistlib.dumps(info))
(app / 'PkgInfo').write_bytes(b'APPL????')
PY
    xcrun vtool -show-build "$ios_app/ClearMic" > "$ios_output/build-version.txt"
    python3 - "$ios_output/build-version.txt" "$ios_sdk" <<'PY'
import pathlib, re, sys
metadata = pathlib.Path(sys.argv[1]).read_text()
expected = 'IOS' if sys.argv[2] == 'iphoneos' else 'IOSSIMULATOR'
assert re.search(r'platform\s+' + expected + r'\s', metadata), metadata
assert re.search(r'minos\s+17\.0\s', metadata), metadata
print(metadata)
PY
    echo "Built unsigned SDK artifact: $ios_app"
done
