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

Run `scripts/render-ui.sh` to render actual SwiftUI fixtures at 17 widths
from 320 to 1280 points, including both sides of each layout threshold, in
light and dark appearances into `build/ui/`. Optional width arguments narrow
the render, for example `scripts/render-ui.sh 320 740`. The helper draws its own offscreen hosting
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

## Bass and air EQ, 0.1.7

Twenty-two tests pass. Shelf tests exercise boosts and cuts at the low/high
passbands, the half-gain corner frequencies, and the unaffected opposite
frequency range. A settings round-trip test proves existing 11 dB input
trim, 8 dB output and enabled cleanup survive migration with flat new bands.
Native light/dark layouts are rendered from 320 to 1080 points.
Actual voice preference and listening quality remain a live user check.

## Reorganized controls, saved voices and studio finish, 0.1.7

Twenty-nine tests pass. Additional checks cover split-band high-frequency
attenuation with low-frequency retention, a finite reverb tail that decays,
dry bypass/mute with reverb, and save/overwrite/reload of a named preset
while preserving source, channel, headphone route/level, mute and bypass.
These include actual sample processing and isolated preferences, not UI
state-only assertions. The light/dark native renders cover 320–1080 points.

The save dialog, opened menus, VoiceOver and subjective de-essing/reverb
quality remain live user checks. No claim is made that effects alone make
a voice studio-quality. After update, save the existing baseline, then
compare small de-ess amounts and optionally a low room mix while listening.

The mute transition test also verifies that speech received while muted
cannot return in a reverb tail after unmuting. With noise cleanup, bass/air,
de-essing and room mix enabled, five release CPU checks processed all frames
with finite, bounded, nonzero output. Block medians were 0.272–0.273 ms,
p99 0.354–0.373 ms, and maxima 0.396–1.502 ms for 10 ms blocks on this Mac.
This excludes live Core Audio/Bluetooth scheduling and is not a latency
or dropout guarantee.

Reconnect tests remove the active device from an injected inventory, verify
Source Lost and teardown, try reconnection while absent, then return the same
UID with a new device ID and resume via Reconnect without selector changes.
A separate case keeps the device listed but stalls frame counts; the stream
watchdog also enters Source Lost and permits a fresh route. Both tests use
isolated route boundaries and do not unplug the user's actual microphone.
Denoise is now in the Voice EQ heading; its DSP order is unchanged.

The footer reads Connected as the enumerated virtual microphone name only
while processing is running. Its Off action uses the tested stop path; On
uses the existing start path. Normal instructional status strings are no
longer emitted. Optional messages now contain errors or setup/source-loss
information and appear only when present. The footer actions still require
a live UI check.

Monitoring status uses a headphones label and the mute indicator is an
independent mic-slash label, so both can be shown together. Monitor On
reflects an active monitor route, not just a saved toggle. A lifecycle test
verifies Listen can restart after Stop and can disable headphone monitoring
without stopping virtual mic processing.

## Impeccable layout and state audit, 0.1.8

The audit applies the workspace Impeccable grid, spacing, responsive, copy and
state disciplines to native SwiftUI. There is no web/CSS detector in this repo.

| Finding | Resolution |
| --- | --- |
| Listen detached from the other action keys | One leading row, with equal cap dimensions at every width |
| Knobs drift across sections with different control counts | Shared full-width columns for every section; short rows keep their tracks |
| Narrow layouts center short groups | Explicit leading alignment and a wrapping button layout |
| Oversized header and misplaced monitor level | Header removed; independent level below Headphone Output |
| Verbose Studio Finish and no section bypass | Paragraph removed; toggle bypasses effects while preserving amounts |
| Saved voices hidden in a selector; modified identity lost | Voice buttons, dirty dot, two-click overwrite target/confirmation |
| Connection label and power control bunched together | Flexible gap across the full footer width |
| Channel selector competes with the microphone name | Compact adjacent 1/2/Both control; Both averages physical inputs 1 and 2 |
| Permissions unexplained before first use | Three-page setup with persistent completion and reopenable help |

Native fixtures cover widths 320, 379/380, 391/392, 439/440, 539/540, 663/664,
739/740, 787/788, 1080 and 1280 points in both appearances. Fixture preferences
are isolated and removed afterward; no personal presets, microphone capture,
desktop capture or UI automation are used. Long voice names, a modified saved
voice, overwrite confirmation and all three setup pages are also rendered.

Thirty-three tests pass through `scripts/check.sh`, followed by release app
and universal driver builds with verified local signatures. Added assertions
exercise two-click saving without discarding edits, cancellation after further
processing edits, routing/mute exclusion from preset dirtiness, persisted
completion without a permission request, old preset migration, retained studio
amounts when bypassed, and equal-weight Both routing for interleaved and separate
buffers. Missing blend input produces silent outputs and a routing error.

Static layout and injected-boundary checks do not prove live window dragging,
VoiceOver, actual permission dialogs, a completed installed-app update or physical
audio capture. Those remain user journeys to verify in the installed application.

## Public-beta acceptance gate

Record the exact source SHA and installer checksum with each result. The following
remain **pending** until exercised on a test Mac; offline tests do not satisfy them.

- Fresh download and installation under normal Gatekeeper settings without Xcode.
  Confirm the app/driver appear and system default audio devices stay unchanged.
- First launch, denied microphone access, permission recovery and reopened setup.
- Explicit driver loading after ending calls; no restart from the installer itself.
- Physical 48 kHz capture into a browser recorder and a call app. Confirm audible
  processing, dry bypass, mute and silence after Stop/Quit; preserve private audio locally.
- Wired-headphone Listen at low volume; no automatic physical-speaker monitoring.
- Source unplug/reconnect, sample-rate mismatch, sleep/wake and no silent fallback.
- At least a one-hour recording with controls changing: listen for clicks,
  dropouts and drift, and note CPU load and the exact hardware/software combination.
- An installed previous release updates through Sparkle, retaining saved voices,
  preferences and driver. Confirm the update opens and audio still flows.
- Uninstall the app and only ClearMic's driver, restart, and confirm the virtual
  input is gone while unrelated drivers remain. Reinstall and check preferences.
- Exercise Apple Silicon and Intel separately before claiming both are supported;
  verify the oldest supported macOS version and a current macOS release.

Only a local test Mac with explicit installer approval should be modified. Do not
restart Core Audio or install/remove drivers as part of automated checks.

## Public-beta preparation, 0.1.9

Local verification on Apple Silicon: 33 DSP/session tests, 9 iOS route tests,
6 iOS release-tool tests, 4 macOS release refusal tests and the appcast test passed.
Host app and universal driver builds passed. A separate universal app/driver
installer was built and expanded without installation; both architecture slices,
fixed payload paths, version 0.1.9 (10), audio-input entitlement, nested signatures,
licence resources and absence of installer scripts/upstream branded icon were checked.
The native UI fixture at 740 points and original icon were visually inspected.

SwiftPM's first binary-artifact download stalled on this host. The exact pinned
Sparkle 2.10.0 archive was downloaded with curl, its SHA-256 matched against the
upstream package manifest, and SwiftPM's artifact cache was populated before
rerunning the checks. No dependency version or checksum was changed. A fully
unassisted first download on a fresh Mac remains unverified.

Independent static review found and resolved the macOS Bash empty-array issue
and missing hardened-runtime audio entitlement. Packaging inspection also caught
and corrected lipo argument ordering in release preparation and preview CI.
Developer ID Installer identity and a configured notarization profile remain
prerequisites; no notarization, driver installation, Core Audio restart, live
capture or installed-app update was performed. No public release/feed was changed.
