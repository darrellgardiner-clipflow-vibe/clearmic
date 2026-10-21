# ClearMic controls

ClearMic is a native macOS voice processor. Its controls should read like a
small desktop instrument, with full-bleed materials, tactile caps and an inset
LCD. The app follows system appearance and supports windows down to 320 points.

## Tokens and materials

Use the existing `Panel` colours in ContentView.swift. Orange identifies active
controls and EQ bands. Near-black case, charcoal caps and black sockets must
remain distinct in dark mode. The LCD uses static scanlines and a vignette.
Decorative layers must not intercept input or accessibility navigation.

Existing typography uses the system face and monospaced control labels.
Existing material radii are 8–11 points. Frequently used controls animate in
120–160 ms and respect Reduce Motion. Controls keep their size when selected.

## Layout

- Bypass, Mute, Listen and Start/Stop share one leading action row at every width.
  No large brand header consumes the workspace.
- Source and Headphone Output share aligned headings and selector baselines.
  Routing stacks below 740 points. Channel is a compact accessory to Source;
  headphone listening level belongs below Headphone Output.
- Level & Dynamics, Voice EQ and Studio Finish share the same full-width knob
  grid. A short row keeps the same column positions as a long row. Knobs never
  redistribute or center to fill a short row.
- The grid changes between two and six columns according to available space.
  Page padding is 16 below 440 points and 28 otherwise. Section spacing is 28.
- Voices wrap as individual buttons, with the final row aligned to the leading
  edge. Long names truncate inside the available width.
- Connection status anchors left and its power action anchors right, separated
  by flexible space. Setup help lives in the small-print footer.

## Interaction states

A saved voice is selected, modified, awaiting overwrite confirmation, or idle.
A modified voice keeps its identity and shows an orange dot. While modified,
clicking a saved voice chooses an overwrite target without changing the sound.
Clicking that target again writes the current processing settings. A processing
edit or Cancel cancels confirmation. A different target needs its own second
click. When clean, a voice button loads the saved settings immediately.

Studio Finish has one section switch. Off removes de-essing and reverb from the
signal while retaining both amounts. Its disabled knobs cannot be adjusted.
Denoise remains before EQ in the signal chain regardless of its visual location.

The first-run setup explains microphone access, the separate virtual-driver
installer and headphone monitoring. Reading setup never requests permissions
or starts capture. Help reopens setup. Completion persists locally.

## Verification

Run `scripts/render-ui.sh` for native fixtures immediately above and below each
layout threshold, both appearances, long and modified preset names, overwrite
confirmation and all setup pages. It uses isolated preferences and no real audio.
Run `scripts/check.sh` for preset persistence, permission/lifecycle behavior,
studio bypass and channel routing. Static renders do not prove keyboard focus,
menu interaction, VoiceOver or physical audio capture.

## App icon

The original orange-red C remains the primary mark on a warm white macOS tile.
Its broad ribbon has opposing diagonal terminals. A smaller, horizontal
microphone body sits inside the opening, with a curved rear nested into the C’s internal
curve and a rounded end facing right. A consistent 28–30 point white channel
separates the rear from the C on the 1024-point canvas. It has no connector or stand. A rising diagonal waveform knockout
crosses the lower C, microphone body and upper C terminal, revealing the white
tile beneath. Its shared diagonal and the nested rear give the mark a deliberate
construction without adding a stand or grille. The C and microphone use separate geometry, with white space between
them so the C stays dominant. The complete mark is shifted left (20 points on
the 1024-point canvas) for optical balance; the tile stays in its original position.

Both shapes read as recesses cut into the white surface. Inner shadows cast
from each inverse silhouette fall into the coloured cavity, and a pale lip
defines the surface edge. There is no external shadow beneath the coloured
mark; the tile retains its own soft shadow. Generous white space and a continuous
tile contour keep the icon readable in the Dock. The waveform remains at every
size, with a heavier stroke at 16 and 32 pixels (20 canvas points versus 14 at
larger sizes).
This asset does not change the controls' existing colours or materials.

`scripts/build-icon.swift` owns the original paths and renders every iconset
representation directly at its target resolution, from 16 through 1024 pixels.
The app and HAL driver share the resulting `ClearMic.icns`; no Apple or
BlackHole artwork is shipped. `scripts/build-driver.sh` generates and packages
the icon, and `scripts/build-app.sh` copies that same asset into the app.
Verify with `scripts/check.sh`, then inspect the generated iconset at small and
large sizes and confirm both bundles contain the same icon. Build success alone
does not prove how an installed icon appears in Finder or the Dock.
