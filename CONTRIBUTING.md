# Contributing to ClearMic

Bug reports, documentation improvements and focused pull requests are welcome.
Use [GitHub issues](https://github.com/darrellgardiner-clipflow-vibe/clearmic/issues)
for support and proposals. Discuss larger changes before implementing them.
Be respectful, provide reproducible evidence and keep private recordings private.

## Build on a clean Mac

Install Xcode and select its command-line tools in Xcode Settings → Locations.
Requires macOS 14+, Swift 5.9+, Python 3 and Git. No signing account, studio
credential library, installed driver or microphone access is needed for checks.
The first build downloads the pinned Sparkle dependency; DSP runs offline.

```sh
git clone https://github.com/darrellgardiner-clipflow-vibe/clearmic.git
cd clearmic
scripts/check.sh
open build/ClearMic.app
```

`scripts/package.sh` prepares a local unsigned installer without installing it.
Build output stays under ignored `build/` and `.build/`. See
[release preparation](docs/releasing.md) for public binaries and
[iOS](ios/README.md) for the separate experimental iPhone app.

## Make a change

Read [architecture](docs/architecture.md), keep changes focused and explain the
observable before/after behavior in your PR. Run `scripts/check.sh` and relevant
regression checks. CI also runs the iOS route and release-tool tests. Describe
checks you actually ran and hardware/platform checks that remain unverified.

Keep audio callbacks in C++ with no allocation, blocking, logging, Swift objects
or filesystem access. Controls use lock-free atomics. Never automatically route
microphone audio to speakers or change system default input/output devices.
Driver installation is always an explicit administrator action. Checks must not
install drivers or restart Core Audio.

Preserve pinned upstream sources and notices under `vendor/`. BlackHole build
customization belongs in `Driver/ClearMicConfig.h`. Contributions to ClearMic
are under the repository's GPLv3 licence; include provenance and compatible
licence notices for new dependencies. Do not include third-party branding.

Maintainers' local AGENTS.md workflow integrations are not prerequisites for
external contributors. Forks should use their own app identifiers, release URLs
and update-signing keys before distributing binaries; see [updates](docs/updates.md).
