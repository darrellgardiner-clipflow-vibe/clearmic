# Architecture

## User workflow

Install the app and driver, select one physical input channel, start processing,
then select ClearMic in the recording/call app. Closing the app window keeps the
route alive in the menu bar. Stopping or quitting stops the route. Optional
Listen adds a selected headphone output with drift correction and an independent
level. It can run without the virtual driver so users can audition effects first.

## Data ownership

- `Session` owns editable/persisted voice settings and application state. It
  writes preferences and controls on the main thread. Device UIDs are persisted;
  transient Core Audio IDs and meters are not.
- `AudioRoute` owns one private aggregate, one IOProc registration and one DSP
  allocation. Teardown stops the callback before destroying registration,
  aggregate and processor. A failed start uses the same teardown path.
- `CMProcessor` owns biquad, compressor and limiter state exclusively on the
  render thread. Controls cross via bounded atomic snapshots; meters cross via
  lock-free atomics. The callback never enters Swift.
- The pinned driver owns transport between the hidden send device and visible
  microphone. No proprietary transport or capture engine is used.

The app exposes effects through `Session.settings`, starts through `start()` and
stops through `stop()`. The UI never coordinates Core Audio resource creation.

## Audio path

1. Resolve the selected physical source, `ClearMic_UID` and `ClearMic_2_UID`.
2. Validate 48 kHz and the source channel. Create a private aggregate
   with the source first and hidden send second. Source is the clock master;
   send has drift compensation enabled. The aggregate uses `stacked = false`.
3. Validate stream format and complete input/output channel counts before I/O.
4. The C++ IOProc clears output buffers, selects one input channel, processes
   mono, and writes it only to the two send channels. Physical output channels
   remain zero unless explicitly selected for Listen. Interleaved and separate
   float buffers are supported.
5. The driver makes those two equal channels readable as the ClearMic input.

Live probing on macOS 26 found that `stacked = true` creates an output-only
device and drops the physical input streams. `false` preserves input and
separate output streams. The SDK's terse comment led the initial design review
to the wrong conclusion. The route probe now uses the application's actual
configuration and checks the resulting channel counts before any I/O starts.

The process-private aggregate disappears on process exit. The installed public
microphone remains. The app never changes system default devices or silently
falls back to another microphone. Disconnect recovery currently requires Start;
there is no automatic UID/model matching beyond the saved exact UID.

## Processing

Input trim → second-order Butterworth high-pass → 280 Hz bell, Q 0.8 →
3.5 kHz bell, Q 0.7 → peak compression → output gain → −1 dBFS limiter.
Compression uses a 10 ms attack and 120 ms release. Bypass returns the raw
selected input, including bypassing the limiter. Mute always wins.

Each controls write marks an atomic snapshot in progress, publishes bounded
values, then completes it. The callback makes one attempt to read a coherent
snapshot per block; if a write overlaps it keeps the previous controls. There
is no spin loop. Input/output gain changes are smoothed over 5 ms.

## Synthesis decision

Two independent designs compared a new HAL driver with a customized BlackHole
driver. Both converged on a private aggregate and a C/C++ IOProc for clock and
channel ownership. The BlackHole design is the base because it supplies an
existing, attributed transport with a documented hidden-mirror configuration.
GPLv3 is acceptable for this public open-source product.

From the new-driver candidate, retain strict lifetime ownership, persistent UID
selection and failure-to-silence behavior. Reject writing a new HAL object and
timestamp implementation for the first release. It adds maintenance without
improving this microphone path. The independent cross-judge also selected this
design and identified atomic ordering and abrupt controls as hazards. Sequentially
consistent atomic snapshots and 5 ms mute/bypass/filter ramps address those.
The factory UUID was checked against upstream and differs.

## Tradeoffs and remaining work

We accept a GPLv3 driver and administrator-approved installation in exchange
for a microphone ordinary apps can select. We accept 48 kHz and one mic in
exchange for a small inspectable route. Monitoring is off at launch and requires
an explicit headphone destination.

The first build still needs live driver installation, browser capture and
endurance verification. Developer ID signing/notarization are distribution
prerequisites. Device changes are polled every two seconds and currently require
a manual restart of processing after disconnect. Monitoring output must also
be convertible to the aggregate's 48 kHz stream. These limits must not be described as passed tests or finished
release behavior.

## Speech denoiser

The 48 kHz processor owns an RNNoise v0.2 state allocated before I/O starts.
Its compiled model and tables are immutable; each route has separate state.
The chain is input trim → optional RNNoise blend → high-pass/EQ → compressor
→ output gain/limiter. Bypass selects the original sample and Mute wins.

Fixed 480-sample input/output arrays bridge arbitrary callback sizes to the
model frame size. Float amplitudes are scaled to/from the library's PCM units.
The model runs continuously while the route is active; enabling cleanup
ramps its mix over 50 ms without allocating or resetting the model in the
callback. Disabling cleanup returns to the original undelayed path. This
transition blends signals with different delay briefly; final listening
quality and Bluetooth latency remain live verification requirements.

The processor reads the cleanup flag in the same coherent atomic snapshot
as the other controls. Models, buffers and library state are destroyed only
after the audio callback has stopped. Neither the render loop nor the model
frame-processing call performs file access, allocation, logging or locking.
The bundled source/model provenance and compatibility shim are documented
in vendor/RNNoise/PROVENANCE.md.

## Bass and air shelves

The 120 Hz bass and 8 kHz air filters use RBJ biquad shelves with slope 1.
They share the existing coefficient ramps, control snapshot and limiter.
New atomic values occupy slots 8/9 and are bounded to ±12 dB before entering
the snapshot. The UI computes the same shelf response for its LCD curve.
Legacy saved settings merge the new bands at 0 dB without changing input
trim, makeup gain or cleanup. Both shelves are flat in Natural and Flat.

## Studio finish and preset ownership

The split-band de-esser follows EQ and precedes compression. A 4.5 kHz
one-pole split feeds a fast-attack/60 ms release high-band detector, with
up to 9 dB high-band reduction scaled by the amount control. Gain changes
use the existing smoothing coefficient. It is a simple de-esser, not a
trained sibilance classifier.

A fixed-buffer Schroeder room follows compression and precedes output
gain/the limiter. Four damped parallel combs feed two allpass diffusers.
The wet mix is bounded to 25% and smoothed. Delay buffers are allocated as
part of the processor before I/O. Mute clears the room once and prevents
new muted speech entering it. Bypass remains dry. No effect allocates,
locks or logs in the callback.

VoicePreset owns a named processing snapshot. VoiceSettings.presetSettings
strips routing, listening level, mute and bypass before serialization.
Session owns save/replace/load in its injected UserDefaults. Applying a
preset preserves those session controls, then updates the current route
through the existing coherent atomic controls snapshot.

Source loss is session state independent of device enumeration. Both a
disappearing/changing active input and a stalled callback counter stop the
route and set sourceLost. Reconnect refreshes enumeration and starts only
the saved UID; successful route creation clears the state. Returning device
IDs can differ, and replugging alone never starts capture.
