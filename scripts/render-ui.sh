#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
xcrun swiftc -parse-as-library Sources/ClearMic/AudioRoute.swift Sources/ClearMic/Session.swift \
  Sources/ClearMic/ContentView.swift Sources/ClearMic/HardwareSelectors.swift scripts/RenderUI.swift \
  "$bin_dir/ClearMicAudio.build/Processor.cpp.o" -I "$bin_dir/ClearMicAudio.build" \
  -lc++ -o build/ClearMicUIRenderer
exec build/ClearMicUIRenderer "$PWD/build/ui"
