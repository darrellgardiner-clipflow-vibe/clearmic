#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh
python3 scripts/package-component.py all
echo "Installer created. Quit audio apps before installing; use Load microphone in ClearMic if needed."
echo "Development package is unsigned and not notarized. See README.md for distribution requirements."
