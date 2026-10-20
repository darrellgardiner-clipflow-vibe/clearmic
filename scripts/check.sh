#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
scripts/build-app.sh
echo "Checks passed. Hardware and browser routing require the separate live smoke test."
