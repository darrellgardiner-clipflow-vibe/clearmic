# In-app updates

ClearMic embeds Sparkle 2.10.0, pinned through Swift Package Manager. The app
menu and menu-bar panel expose Check for Updates. Automatic checks are enabled;
installation remains user-controlled. Updates use an HTTPS appcast and Ed25519
archive signatures, verified before extraction. System profiling is disabled.

App updates replace the app bundle and preserve preferences. The virtual driver
is installed separately and remains in place. App updates therefore do not
require repeating driver installation. If a future release changes the driver,
that component will require a separate administrator-approved update/reload.

## Maintainer workflow

The first signing key was generated locally with CryptoKit. Its private seed is
stored outside Git in `~/.local/share/clearmic-signing/ed25519.key`
with owner-only permissions. Only the public key in Release/public-key.txt is
committed. Keep a secure private-key backup; losing it breaks update continuity.
Never put the private key or its contents in commits, logs, issues or releases.

`scripts/create-update-key.swift` creates a key only if none exists. Forks must
change the update-feed/download URLs and create their own key. Do not regenerate
or replace a published app's key casually.

For each release, increment both the marketing version and integer build:

```sh
CLEARMIC_VERSION=0.1.2 CLEARMIC_BUILD=3 scripts/prepare-update.sh
```

The script creates a signed zip and appcast locally. Review and upload the zip
to the matching GitHub release, then commit/push Release/appcast.xml. It never
publishes automatically. The feed must point to an existing uploaded artifact.

Anyone can verify an archive without the private signing key:

```sh
swift scripts/verify-update.swift Release/public-key.txt Release/appcast.xml build/updates/ClearMic-0.1.0.zip
```

Never overwrite a published archive or reuse its build number.

The local prototype is ad-hoc signed. A general distribution release still
needs Developer ID signing of the app and its nested code, plus notarization.
Ed25519 update signatures do not replace Gatekeeper/notarization. An actual
older-to-newer installed-app update must be tested before claiming that journey
is verified. Building a signed archive alone is not that test.

References: [Sparkle setup](https://sparkle-project.org/documentation/),
[programmatic API](https://sparkle-project.org/documentation/programmatic-setup/).
