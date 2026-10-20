# Verification

## Automated checks

Run `scripts/check.sh`. Offline tests exercise actual DSP samples and callback
buffers. They cover dry bypass, mute precedence, high-pass response, the two EQ
bands, the compressor static curve, limiter bounds, invalid controls/samples,
selected-channel routing with silent physical outputs, independently attenuated
headphone monitoring and mute ramps.

The script also builds the SwiftUI application and universal HAL driver and
verifies their local signatures. A successful build is not proof of microphone
permission, driver loading, correct clock behavior or Riverside capture.

## Live user journey

`scripts/probe-route.sh` lists devices and IDs. Pass an input ID and optional
output IDs to check the app's real route configuration without starting capture.
On the development Mac, the USB codec input plus its stereo output and AirPods
produced 2 input / 4 independently addressed output channels. An input-only
route is checked separately. These probes caught and reproduce the initial
multi-output-versus-aggregate configuration bug.

Prerequisites: installed ClearMic driver loaded after restart, microphone
permission, a physical 48 kHz source, headphones, and a browser with Riverside.

1. Note the system input/output selections. Open ClearMic, select the interface
   and Input 1, and start. Both meters should move with speech.
2. Open Riverside and choose ClearMic. Record speech while changing low mids
   and clarity. Play back and confirm the changes are audible.
3. Turn Bypass on. The selected channel should be dry in both virtual channels.
   Turn Mute on; the recording should reach silence even with Bypass enabled.
4. Stop ClearMic with the browser still capturing. Confirm silence without a
   repeated buffer. Start again and confirm speech returns.
5. Disconnect the source. The app should stop with an explanation. Reconnect
   the same input, refresh if necessary and start again. No other microphone
   should be selected automatically.
6. Quit/reopen ClearMic. Confirm controls and source selection persist and
   capture stays stopped until Start is pressed.
7. Confirm system default input/output selections have not changed. Keep other
   installed audio drivers in place throughout.
8. Record a long session while moving controls. Check for dropouts, clicks,
   drift, overloads and non-finite samples before calling the app release-ready.

Teardown: stop this app's route, quit its UI, close the recording, and keep any
recorded speech private. Uninstall only ClearMic's app/driver if requested.

## Current evidence

The local build passed ten offline DSP/routing tests and compiled the
app and universal driver on Apple Silicon with Xcode 26.6. Live-driver loading,
real microphone capture, browser capture, sleep/wake and long-session tests
have not yet been performed. The driver requires administrator installation;
the build scripts deliberately do not do that as a test side effect.
