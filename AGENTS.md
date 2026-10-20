# ClearMic development

Read `~/.config/development-workflow/CONTRACT.md` and its default project module.
Run `python3 ~/.config/development-workflow/devflow.py context --repo .` before
choosing tools or crossing repositories.

ClearMic processes one microphone into a virtual input for recording and calls.
Read README.md and docs/architecture.md before changing routing. Run
`scripts/check.sh` for DSP behavior and application/driver builds.

Keep audio callbacks in C++. No allocation, blocking, logging, Swift objects,
or filesystem access on the render thread. Controls cross through lock-free
atomics. Never route microphone audio to physical speakers automatically.
Never change the system's default input or output device.

The GPLv3 driver source in vendor/BlackHole is pinned upstream code. Preserve
its copyright and licence. Customization belongs in Driver/ClearMicConfig.h.
Driver installation requires an explicit user action and administrator access.
Do not restart Core Audio or modify another audio driver during checks.

Commit task changes before handoff. Record verification limits honestly.
