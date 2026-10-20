# ClearMic for iPhone: Bluetooth route prototype

This is a small experiment for using a paired DJI or other Bluetooth microphone
before recording with Apple's Camera app. It is not an iOS virtual microphone,
and it does not deliver ClearMic's macOS effects into Camera.

The app selects an input exposed by iOS audio, verifies the actual route, meters
a short microphone test, and prepares the session before you switch to Camera.
Hardware input gain appears only when the current input supports it. No receiver,
account, cloud service or paid API is used by the app.

A paired accessory must expose a supported microphone input. Playback-only
Bluetooth devices cannot be used as microphones. Compatibility with arbitrary
Bluetooth microphones and retention of the route by Camera are unverified.
DJI documents that direct Bluetooth on Mic Mini supports third-party camera apps,
not the native Camera app. This prototype tests the reported route-priming workaround.

## Build and install on an iPhone

Requires iOS 17+, Xcode 26+ with its iOS platform component, and a personal Apple
ID or Apple Developer team for device signing. No signing team is committed.

1. Open `ios/ClearMic.xcodeproj` in Xcode.
2. Select the **ClearMic-iOS** scheme and the **ClearMic-iOS** target.
3. Under Signing & Capabilities, select your team. A personal team may require a
   unique bundle identifier instead of `flow-labs.clearmic`.
4. Connect and unlock the iPhone, trust this Mac if requested, and enable Developer
   Mode on the phone if Xcode requires it.
5. Select the iPhone as the run destination and Run.

If Xcode says the iOS platform is not installed, install the matching component
under Xcode → Settings → Components. The SDK-only artifacts described below do
not bypass provisioning and cannot be installed unsigned on a normal iPhone.

TestFlight distribution requires a configured Apple Developer team and App Store
Connect app. This repository does not publish iOS releases or submit apps automatically.

## Test the actual workflow

1. Pair the transmitter directly in iPhone Settings → Bluetooth. No receiver.
2. In ClearMic, tap Find microphones and allow microphone access.
3. Select the Bluetooth input. Wait for Input ready and the matching verified name.
4. Tap Test microphone and speak. The meter must react to the Bluetooth microphone,
   not just the phone. Stop/reconnect on any mismatch or lost source.
5. Tap Prepare Camera. The microphone test stops, leaving the audio session prepared.
6. Switch to Apple's Camera app yourself and record a short video. Put the iPhone
   farther away and speak close to the Bluetooth mic. Also test touching the phone
   near its built-in microphones to distinguish which input was actually recorded.
7. Play the video back. Repeat after stopping/starting a second video, after locking
   the phone, and after reconnecting the transmitter. Compare once without ClearMic.
8. Return to ClearMic and use Reconnect & recheck for another attempt. Stop releases
   its audio session. Share route diagnostics only if you choose to.

Last verified in ClearMic means exactly that. The app cannot inspect Camera's
recording input, and system route notifications during handoff are not proof of
what Camera recorded. A real device test is required before claiming success.

## Permissions and temporary audio

Microphone access is requested only on Connect/Find/selection. The level test
writes at most 30 seconds of mono PCM into the app's temporary directory for
AVAudioRecorder metering. Stop, handoff, test completion, source loss and errors
stop the recorder and delete that file. The next app launch also removes a file
left by a crash. No recordings are exported or uploaded.

There is no playback/monitoring output, Core Bluetooth scan, camera capture,
photo-library access or background-audio entitlement. Preparing Camera does not
continue the level test or run a background loop that fights for microphone access.

## Architecture and checks

`RouteCore` owns session state and has an injected `MicrophoneHardware` boundary.
The iOS adapter owns AVAudioSession, AVAudioRecorder and notifications. It uses
Apple's recorder rather than a custom Swift render callback. Input selection is
verified against the actual route after settling. Permission and route requests
have generation guards; Stop or a newer request cancels stale completion.

Lost inputs and interruptions stop testing and require explicit reconnection.
They never silently substitute the phone microphone or resume capture. Camera
handoff is a separate experimental state and never reports Camera input as verified.

```sh
swift test --package-path ios/RouteCore
scripts/build-ios-sdk.sh
```

The SDK build script compiles and links the real app for ARM64 iPhone and ARM64
simulator using installed SDKs, then checks Mach-O platform/version metadata.
It does not sign, install, boot a simulator, download a runtime or access microphones.
Artifacts live in ignored `build/ios-sdk/{iphoneos,iphonesimulator}/ClearMic.app`.

Nine host-run tests cover discovery without automatic selection/capture, permission
denial and stale permission races, actual-input checks, selected-source loss and
explicit reconnect, bounded meters/test duration, recording failure, interruptions,
media reset, gain bounds and Camera handoff without automatically reclaiming input.
Both SDK targets compile without diagnostics. On the Mac mini, the nine route
tests, normal Xcode simulator build and unsigned Release device archive pass
with Xcode 26.6 and the installed iOS 26.5 platform. UI execution, system
permission prompts, real Bluetooth levels, temporary-file cleanup on-device and
Camera route retention remain unverified. The macOS app and updater are not
changed by this prototype.

## Platform references

- [Apple: selecting a preferred input](https://developer.apple.com/documentation/avfaudio/avaudiosession/setpreferredinput(_:))
- [Apple: available inputs](https://developer.apple.com/documentation/avfaudio/avaudiosession/availableinputs)
- [Apple: Bluetooth hands-free inputs](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetoothhfp)
- [DJI Mic Mini direct Bluetooth limitations](https://www.dji.com/mic-mini)

## Development host

The active development checkout is `~/Developer/labs/clearmic` on the Mac mini,
beside Link Inbox. Use the mini for iOS simulator builds and device archives;
its Xcode installation includes the required iOS platform and simulator runtime.
The laptop checkout is retained as a copy. No app preferences or signing secrets
were transferred. Link Inbox's existing signing identities and credential store
on the mini are the reference for adding ClearMic's own TestFlight release flow.
The release identity is `flow-labs.clearmic`. TestFlight is distributed to the
existing owner through an Internal group; it is separate from the macOS updater.

From this repo on the mini:

```sh
swift test --package-path ios/RouteCore
xcodebuild -project ios/ClearMic.xcodeproj -scheme ClearMic-iOS -destination 'generic/platform=iOS Simulator' -configuration Debug -derivedDataPath build/ios-simulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/ClearMic.xcodeproj -scheme ClearMic-iOS -destination 'generic/platform=iOS' -configuration Release -derivedDataPath build/ios-device -archivePath build/ClearMic-iOS.xcarchive CODE_SIGNING_ALLOWED=NO archive
```

The archive is unsigned preparation, not an installable or uploaded TestFlight
build. Signing/export and the new app record remain separate release steps.

## TestFlight maintenance

The internal TestFlight app is [clear-mic](https://appstoreconnect.apple.com/apps/6824866849/testflight),
App Store Connect ID `6824866849`. Version 0.1.0 build 23 was uploaded from the
mini on 2026-10-20 from commit `cf73f33d7bf051ec379a3ebee4328e3bac0618db`.
Apple reports `VALID` and `IN_BETA_TESTING`, with the existing owner in the
Internal group and that build assigned. Accept the TestFlight invitation on an
iPhone to install. Future uploads to the Internal group are automatically
available to its tester.

The signed IPA's bundle/version/build, App Store provisioning profile and code
signature were verified. The app was installed and launched in an iOS 26.5
simulator and its first screen inspected. All nine RouteCore tests passed;
the release tooling has five tests, including app-scoped tester creation and
idempotent setup. This does not verify a physical Bluetooth microphone or
Camera's recorded input. Follow the device workflow above for that acceptance.

Release settings live in `ios/Release.json`. `scripts/ios-release.py` resolves
TEAM_ID, ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID and CLEARMIC_SIGNING_KEYCHAIN at runtime
through the existing studio credential library on the mini. It uses an already
unlocked keychain when available; only a locked keychain needs the existing
CLEARMIC_SIGNING_KEYCHAIN_PASSWORD credential. Credential values are redacted from build
logs and never committed. No secrets are copied from Link Inbox or the laptop.

```sh
cd ios
make test
make ios-register          # idempotently reserve the bundle identifier
python3 ../scripts/ios-signing-setup.py  # once, ClearMic-only certificate and profile
make ios-archive           # unsigned archive, then ad-hoc signature
make ios-export            # fresh archive, signed App Store IPA
make ios-upload            # fresh archive, signed export and upload
make ios-status            # processing state and internal beta availability
make ios-enable-testing    # existing owner only, no external review submission
```

The App Store Connect record is named `clear-mic`, with bundle
identifier `flow-labs.clearmic`, SKU `CLEARMIC-IOS` and locale English US. The API
supports bundle registration, upload and tester management; app-record creation
uses the signed-in App Store Connect website. Tester IDs are scoped to each app;
the release command creates the matching owner by email in the target group rather
than copying a Link Inbox tester ID. These commands do not submit the
app for public App Store review or external beta review.

Commit before archiving. Build numbers come from the commit count, and the
ignored `build/ios-release/manifest.json` records the exact source commit,
version, build and bundle identifier. Increment the source commit for another
upload. Archive/export logs and the IPA stay under `build/ios-release/`.
The signed IPA can be prepared before the browser app record is available.
An upload is not TestFlight availability until processing is VALID and the
owner's Internal group has access to the build.

ClearMic has its own distribution certificate, provisioning profile and keychain
on the mini. This avoids the locked Link Inbox keychain and does not revoke or
replace its identity. Signing setup uses one additional Apple Distribution
certificate, refuses to revoke any certificate at the team limit, and persists
partial progress to avoid issuing duplicates after a retry. Its private key stays
on the mini and is imported into the ClearMic keychain; the temporary PEM is
removed after successful setup. A password-protected identity backup remains in
the owner-only signing directory. The generated keychain password is stored under
ClearMic-specific names in the existing owner-only studio device credential file.
The release export explicitly selects this certificate and profile.
