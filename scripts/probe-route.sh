#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
bin_dir="$(swift build --show-bin-path)"
mkdir -p build
xcrun swiftc Sources/ClearMic/AudioRoute.swift scripts/RouteProbeMain.swift \
  "$bin_dir/ClearMicAudio.build/Processor.cpp.o" "$bin_dir"/RNNoise.build/src/*.o -I "$bin_dir/ClearMicAudio.build" -I vendor/RNNoise/include \
  -lc++ -o build/ClearMicRouteProbe
exec build/ClearMicRouteProbe "$@"
