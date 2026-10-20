# ClearMic

A native macOS app that shapes your microphone before it reaches Riverside,
your podcast recorder, or a call. Select your interface, adjust the voice,
and choose **ClearMic** as the microphone in the receiving app.

ClearMic is an early GPLv3 prototype. It builds an app and a virtual-microphone
driver from source. It is not yet a signed, notarized consumer release.
Hardware/browser validation and long-session testing are still required.

## What it does

- Select one hardware input channel and send it equally to both virtual channels.
- Apply input trim, offline speech noise reduction, a high-pass filter, low-mid EQ, presence EQ, compression,
  output gain, and a −1 dBFS limiter.
- Compare with the raw signal using Bypass, or silence the output using Mute.
- Show live input/output peaks, compressor gain reduction and an EQ display.
- Hear the processed voice through a selected headphone output with its own level.
- Save device selection and effects locally. Keep processing in the menu bar
  after closing the window.
- Leave the system's default microphone and speakers unchanged.

The first version processes one microphone at 48 kHz. It does not capture
application/system audio, mix several sources, record files, host Audio Unit
plug-ins, or mix application playback. It replaces the microphone-processing
workflow, rather than the full feature sets of Audio Hijack and Loopback.

## Setup

Requires macOS 14 or later, Xcode Command Line Tools with Swift 5.9 or newer,
and the full Xcode tools for installer/signing work. The app builds for the host
architecture; the driver builds for Apple Silicon and Intel.

```sh
git clone https://github.com/darrellgardiner-clipflow-vibe/clearmic.git
cd clearmic
scripts/check.sh
scripts/package.sh
open build/ClearMic-0.1.1.pkg
```

1. Quit recording/call apps, then run the installer. macOS asks for administrator
   authentication because the driver installs into `/Library/Audio/Plug-Ins/HAL`.
2. Open ClearMic and click **Load microphone** if the driver is not loaded.
   This requests administrator authentication and briefly restarts macOS audio.
   A full reboot is a fallback, not the normal requirement. The installer never
   restarts audio or the Mac automatically.
3. Open `/Applications/ClearMic.app`. Allow microphone access when you press Start.
4. Choose your hardware microphone/interface and the correct channel. For an
   M-Track Solo XLR microphone, select **USB AUDIO CODEC**, **Input 1**.
5. Set the interface to **48,000 Hz** in Audio MIDI Setup if needed, then press
   **Start processing**. ClearMic does not change the hardware sample rate.
6. In Riverside or your call app, select **ClearMic** as the microphone. Keep
   headphones/speaker output set to your usual device.

The local development app/driver use ad-hoc signatures. The installer is unsigned
and unnotarized. macOS may require explicit approval in Privacy & Security.
Keep Gatekeeper and System Integrity Protection enabled. Public binary releases
will need Developer ID signing and notarization before they can be described as
ready for general installation.

With a PodMic USB through XLR, leave its own USB-C cable disconnected. If an
inline phantom-powered booster is in the XLR path, power it according to its
manufacturer's instructions. The Solo's Direct monitor is the raw hardware
signal. To hear ClearMic effects, choose its headphone output in the app, enable
**Listen**, and set the Solo to **USB** monitoring. Listen starts processing
automatically. Use wired headphones to avoid feedback and Bluetooth delay.
Listen starts off at launch and defaults to
−18 dB. It can run before the virtual driver is installed.

Avoid applying a second voice-enhancement/automatic-gain chain in the receiving
app while tuning ClearMic. The Natural preset is a starting point, not a
calibration for every voice. ClearMic does not currently remove electrical whine.

## Build and verify

```sh
swift test                    # Offline DSP and channel-routing behavior
scripts/build-app.sh          # build/ClearMic.app
scripts/build-driver.sh       # build/ClearMic.driver, universal binary
scripts/package.sh            # Installer for both components
```

Build scripts never install a driver, request microphone access, restart
Core Audio, or change a system default. `scripts/check.sh` runs tests and both
builds. See [verification](docs/verification.md) for the live-device checklist.

To inspect the app UI without installing a driver:

```sh
open build/ClearMic.app
```

The app shows driver/setup status until the driver is installed. Processing
starts only when requested. A disconnect or sample-rate change stops processing
with an explanation; reconnect the saved input and press Start again.
Changing the selected source or channel while processing restarts the route
with that selection. A new source resets to Input 1; selecting while stopped
does not start capture. The interface adapts down to 320 points wide and follows
the system light/dark appearance.

Bluetooth microphones running below 48 kHz are currently unsupported. For
example, the connected AirPods Pro microphone reports 24 kHz even though its
headphone output runs at 48 kHz. The source picker marks unsupported rates and
Start explains the limitation. Use a 48 kHz microphone for capture; selecting
AirPods as headphone output is a separate route. Sample-rate conversion is
required before lower-rate microphones can be supported.

## Architecture and licence

SwiftUI controls a C++ real-time DSP callback. A process-private Core Audio
aggregate combines the selected interface with a hidden output device and
enables drift correction. Processed audio flows through the driver's shared
ring into the visible **ClearMic** input. Audio is processed locally without a
cloud service or paid API. The updater contacts GitHub for its feed and release
downloads; it does not send audio.

The virtual driver is a customized build of
[BlackHole](https://github.com/ExistentialAudio/BlackHole), with unmodified source
pinned and attributed in [vendor/BlackHole/UPSTREAM.md](vendor/BlackHole/UPSTREAM.md).
ClearMic is GPL-3.0; see [LICENSE](LICENSE). The app is independent of Rogue Amoeba,
RØDE and Existential Audio. Their proprietary code and visual assets are not used.

Read [architecture](docs/architecture.md) for data ownership and tradeoffs, and
[research](docs/research.md) for the source-based product comparison.

## Remove the prototype

Quit ClearMic and audio apps. Remove `/Applications/ClearMic.app` and only
`/Library/Audio/Plug-Ins/HAL/ClearMic.driver` using Finder with administrator
authentication, then restart the Mac. Leave other HAL drivers in place.
Local preferences belong to the `org.clearmic.app` defaults domain.

## Updates

Sparkle provides **Check for Updates** in the app menu and automatic update
checks. Signed app updates preserve preferences and the installed driver.
Driver changes are a separate administrator step. See [update maintenance](docs/updates.md)
for signing, feed publication and the remaining installed-update test.

## Speech noise reduction

Enable Speech Noise Reduction to reduce background noise while adding gain.
It uses a bundled RNNoise model locally, with no account, network access or
usage fees. Input trim feeds the denoiser; EQ, compression and output gain
follow it. Natural enables cleanup, and Flat disables it for comparison.
Bypass remains dry, and Mute silences both outputs.

Noise reduction adds frame buffering and model lookahead. Bluetooth monitoring
adds its own delay. Compare on/off with your own voice: cleanup can alter
consonants and voice texture and cannot remove all room echo or background speech.
The bundled model runs while processing to keep comparisons responsive. Stop
processing to release the audio route and denoiser. Third-party notices are
in vendor/RNNoise and the application resources.
