#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${CLEARMIC_VERSION:-0.1.0}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Use a numeric x.y.z version." >&2; exit 1; }
key="$HOME/Library/Application Support/ClearMic/Signing/ed25519.key"
[[ -f "$key" ]] || { echo "No local signing key. See docs/updates.md." >&2; exit 1; }
scripts/build-app.sh
mkdir -p build/updates
ditto -c -k --sequesterRsrc --keepParent build/ClearMic.app "build/updates/ClearMic-$version.zip"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --ed-key-file "$key" \
  --download-url-prefix "https://github.com/darrellgardiner-clipflow-vibe/clearmic/releases/download/v$version/" build/updates
cp build/updates/appcast.xml Release/appcast.xml
echo "Prepared signed archive and appcast. Upload the archive to the matching GitHub release before publishing the feed."
