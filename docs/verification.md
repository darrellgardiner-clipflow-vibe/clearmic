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

## Native UI rendering

Run `scripts/render-ui.sh` to render the actual SwiftUI content at 1080, 820,
600, 420 and 320 points wide in both light and dark appearances into `build/ui/`. The helper draws its own offscreen hosting
view, without desktop capture, microphone capture or UI automation. Inspect
the images for wrapping and control depth. Resize the running app to check
scrolling, keyboard focus and pressed/hover states; the static renders do not
prove those interactions.

For 0.1.2, both native renders were inspected, the ten DSP tests passed, and
the app and driver built with valid local signatures. Physical button press
and hover behavior remains a manual check in the installed application.

The 0.1.3 Load microphone action requests an administrator-authorized normal
termination of `coreaudiod`, following the upstream driver reload approach,
instead of the `launchctl kickstart` action rejected by SIP on the test Mac.
A successful request is not reported as a loaded driver until enumeration
finds both devices. The command is not run during automated verification;
its effect on this Mac remains a manual check via Load microphone.


## Source switching and appearance checks, 2026-10-20

The fourteen tests pass, including four Session tests using isolated preferences
and fake audio/permission boundaries. They exercise restarting active source
selection, resetting the channel for mono input, selecting while stopped,
Stop cancelling queued restarts, rapid repeated selections, and an old permission
response arriving after a newer source starts. No test captures live audio or
changes system default devices. The app and universal driver build and their
local signatures verify through `scripts/check.sh`.

Native renders cover five widths from 320 through 1080 points in both system
appearances. The 320-point dark and 820-point light renders were inspected for
control clipping and wrapping. This checks the real SwiftUI layout, not live
window dragging or audio capture. The installed app still needs a live source
switching smoke test with speech and a system appearance change while open.

The read-only device probe reports the connected AirPods Pro microphone at
24,000 Hz and its output at 48,000 Hz. The engine still requires a 48,000 Hz
input. Source switching fixes do not establish Bluetooth microphone support;
unsupported sample rates are labelled and refused explicitly. No driver was
installed and Core Audio was not restarted during these checks.

## Hardware selectors and display, 0.1.4

Source, channel and headphone selectors use recessed custom menu labels with
standard selection menus. The compressor uses a custom toggle with a native
accessibility representation. Active buttons use the EQ orange and retain the
same 85 by 68 point cap dimensions as inactive buttons. Only an actual press
moves the cap. The display uses static scanlines, gradients and a vignette,
with no timer or animated shader; no frame-rate performance claim is made.

Fourteen tests pass, including four source-switch lifecycle cases. Offscreen
rendering covers light/dark appearance at 320 through 1080 points. Opening
menus, VoiceOver, physical presses and actual microphone switching in the
installed app still require a live user check.

## Dark material revision, 0.1.5

Dark mode uses explicit sRGB near-black case colours, separate charcoal cap
colours and black button wells. Highlight opacity is reduced throughout the
buttons, selector edges and dial collars. Light-mode palette values remain
unchanged. Native light/dark renders at 320 through 1080 points are generated
by `scripts/render-ui.sh`; this revision changes appearance only.

## Speech cleanup, 0.1.6

Nineteen offline tests pass, including steady seeded noise suppression of
more than 8 dB after warmup, synthetic speech retention alongside noise,
callback-size independence, dry bypass/mute precedence and invalid/silent
sample handling. The speech fixture is generated locally, not a user recording.
These checks do not establish perceptual quality for the user's voice.

`scripts/check-noise-budget.sh` times the real release processor for five
1,000-block runs after a 100-block warmup, consuming non-silent PCM and checking
processed frame counts, nonzero output energy, bounds and finite samples.
On this 8-core Mac with load average 9.13, median block time was 0.252–0.253 ms,
p99 0.334–0.356 ms and maximum 0.361–0.422 ms for 480-frame/10-ms blocks.
This is a CPU/DSP microcheck with the normal SIMD model path; it excludes
Core Audio scheduling, device clocks and Bluetooth transport and does not
guarantee live drop-out-free playback.

Live check: update, choose PodMic USB/Input 1 and the actual headphone output,
start, enable Speech Noise Reduction, then compare on/off at unchanged trim
and output settings. Speak normally, pause, and test consonants and breaths.
Check both headphone playback and Riverside recording before accepting the
voice quality and latency. A virtual driver reinstall is not required.
