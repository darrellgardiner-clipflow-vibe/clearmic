# Getting started

ClearMic processes one physical microphone into a virtual microphone that other
apps can select. Requires macOS 14 or later and a microphone running at 48 kHz.
Current downloads are development previews, not notarized consumer releases.

## Install

Download the `.pkg` from [GitHub Releases](https://github.com/darrellgardiner-clipflow-vibe/clearmic/releases/latest).
Quit recording and call apps, run the installer, and authenticate when macOS asks.
It installs `/Applications/ClearMic.app` and
`/Library/Audio/Plug-Ins/HAL/ClearMic.driver`. It does not change your system's
default input/output or automatically restart audio.

Open ClearMic. If the virtual microphone is not loaded, the **Load microphone**
action asks for administrator authentication and briefly interrupts system audio.
Use it only after ending calls and recordings. A Mac restart is an alternative.

## Make your first recording

1. Select your physical microphone under Source. Choose its channel: usually
   Input 1 for an XLR microphone on a two-channel interface. Both blends channels.
2. Press Start processing and allow microphone access. Speak and check the meters.
3. Start with Natural. Use Bypass to compare the raw microphone and Mute to silence it.
4. In the receiving app's audio settings, select ClearMic as its microphone.
   Make a short recording and play it back. Turn off additional voice processing
   in that app while comparing ClearMic's effects.

To audition effects, explicitly select wired headphones and enable Listen.
Start with a low headphone level. Hardware direct monitoring plays the raw
microphone; use your interface's USB/software monitoring to hear the effects.
Listening can work before the virtual microphone is installed. ClearMic never
automatically selects physical speakers for monitoring.

Closing the window keeps processing running in the menu bar. Use Stop/Off or
quit ClearMic to stop. Other apps receive silence when processing is stopped.

## Troubleshooting

- **No microphone permission:** enable ClearMic in System Settings → Privacy &
  Security → Microphone, then quit/reopen the app and try Start again.
- **Unsupported sample rate:** use Audio MIDI Setup to set your microphone to
  48,000 Hz if it supports that rate. ClearMic does not change it automatically.
  Many Bluetooth microphone modes are unsupported; use a 48 kHz USB microphone
  or interface. Bluetooth headphone output is a separate choice and adds delay.
- **Meters move but the call is silent:** check that processing is on, Mute is
  off and the call app has selected ClearMic. Reopen the call app after loading
  the driver so it refreshes its device list.
- **Source Lost:** reconnect the same microphone and choose Reconnect. ClearMic
  does not silently switch to a different microphone or resume on replug alone.
- **Echo or doubled voice:** use headphones, check hardware direct monitoring,
  and avoid monitoring the same microphone in two apps at once.
- **macOS blocks the preview:** keep Gatekeeper and SIP enabled. If you are not
  comfortable evaluating a development build, wait for the notarized beta.

Use the question-mark button to reopen setup. Check for Updates is in the app
menu. App updates preserve preferences and the installed driver; driver updates
require a separate administrator-approved action.

## Uninstall

1. Quit ClearMic and all recording/call apps.
2. In Finder, move `/Applications/ClearMic.app` to the Trash.
3. Choose Go → Go to Folder, enter `/Library/Audio/Plug-Ins/HAL`, and move **only
   ClearMic.driver** to the Trash. Authenticate if requested. Leave other drivers alone.
4. Restart your Mac to unload the removed driver.

Preferences and saved voices remain for a reinstall. To erase them as well,
with ClearMic closed run `defaults delete org.clearmic.app` in Terminal. This
optional step permanently removes saved settings and voices.

## Report a problem

Open a [bug report](https://github.com/darrellgardiner-clipflow-vibe/clearmic/issues/new/choose)
with your macOS version, Mac chip, ClearMic version, microphone/interface, sample
rate, receiving app and steps to reproduce. Do not attach private recordings,
credentials or personal device identifiers. Confirmed live compatibility is
tracked in [verification](verification.md); a successful build is not a hardware test.
