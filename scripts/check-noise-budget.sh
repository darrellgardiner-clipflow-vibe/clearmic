#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
xcrun clang++ -std=c++17 -O3 scripts/NoiseBudget.cpp \
  "$bin_dir/ClearMicAudio.build/Processor.cpp.o" "$bin_dir"/RNNoise.build/src/*.o \
  -I Sources/ClearMicAudio/include -framework CoreAudio -o build/ClearMicNoiseBudget
exec build/ClearMicNoiseBudget
