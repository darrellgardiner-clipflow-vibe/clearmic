# Preparing a public macOS release

The current published downloads are development previews. Do not describe a
build as notarized or hardware-verified until its corresponding checks pass.

## Prerequisites

Use a clean committed checkout on macOS with full Xcode, Python 3 and network
access. Install your Developer ID Application **and Developer ID Installer**
certificates with their private keys in the signing keychain. Apple Distribution
certificates used for iOS are not substitutes. Keep signing secrets outside Git.

Store notarization credentials with `xcrun notarytool store-credentials`, following
[Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
Use a keychain profile so passwords never appear in the release command.
Sparkle nested helpers retain their entitlements during inside-out signing;
see [Sparkle signing](https://sparkle-project.org/documentation/sandboxing/).

Configure these environment variables on the signing host:

```sh
export CLEARMIC_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export CLEARMIC_INSTALLER_IDENTITY='Developer ID Installer: Your Name (TEAMID)'
export CLEARMIC_NOTARY_PROFILE='clearmic-notary'
# Optional; defaults to ~/.local/share/clearmic-signing/ed25519.key
export CLEARMIC_UPDATE_KEY='/absolute/path/to/existing-update-key'
```

Never regenerate the existing update key. Forks must use their own feed URLs,
keys and identifiers. Public release preparation does not use private studio libraries.

## Prepare

1. Increment both values in `Release/version.json` beyond the last published
   release. Commit all changes. The release manifest records that exact commit.
2. Run `scripts/check.sh` and the relevant iOS checks if iOS changed.
3. Run `python3 scripts/release-macos.py --check` to validate prerequisites.
4. Run `python3 scripts/release-macos.py` to build, sign, upload to Apple's notary
   service, staple and assess the universal app and installer. This uploads to
   Apple for inspection, but does not publish a GitHub release or change the feed.

The command checks app and driver architecture slices, signs nested code with
hardened runtime and timestamps, and includes a signed driver component package.
The notarized app is archived again after stapling before its Sparkle signature
is generated. The final installer is separately notarized and assessed.

Outputs are in `build/releases/<version>/`: `.pkg`, app update `.zip`, proposed
`appcast.xml`, and `manifest.json` with SHA-256 checksums and notarization receipts.
The existing repository appcast is untouched. An existing output directory is
never reused: preserve failed output for diagnosis, then move it aside before retrying.
The command stops on missing identities, dirty source, reused build numbers,
notarization failure, assessment failure or update-signature verification failure.

The manual **Package preview** GitHub workflow builds universal unsigned artifacts
for inspection without signing secrets. Those artifacts are not public-beta binaries.

## Accept and publish

Complete the public-beta acceptance checklist in [verification](verification.md)
on a separate test Mac. Record the source SHA, artifact checksum, hardware, OS,
results and limitations in release notes. Builds alone do not establish Intel
execution, microphone permissions, working capture or successful Sparkle updates.

Create a version tag at the manifest's exact commit and attach the prepared
installer and update archive to that release, with checksums and accurate status.
Keep the tagged source available alongside binaries and preserve dependency notices.
Use a prerelease until live acceptance is complete. Never overwrite published assets.
Only after the archive is downloadable at its generated URL should the proposed
appcast replace `Release/appcast.xml` and be committed/published. Publishing the
feed early advertises a missing update. Test an actual previous-version upgrade.

Driver installation/loading must remain a deliberate administrator action.
Build, CI and release preparation must never install a driver, restart Core Audio,
change default devices, or request microphone access as a side effect.
