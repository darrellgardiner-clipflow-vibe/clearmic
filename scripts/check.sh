#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/test-normalize-appcast.py
swift test
scripts/build-app.sh
echo "Checks passed. Hardware and browser routing require the separate live smoke test."
