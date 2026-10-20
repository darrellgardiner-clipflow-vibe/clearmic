# Research notes

Reviewed 20 October 2026 using public documentation and a pinned open-source
driver revision. This establishes documented behavior, not access to proprietary
implementation details.

## Audio Hijack

Audio Hijack captures applications, system audio and physical inputs. Its
sessions connect sources, processors and outputs; it can record files and send
audio to streaming/broadcasting services. This is much broader than microphone
EQ. [Product overview](https://rogueamoeba.com/audiohijack/).

Its effects include EQ and dynamics, with Audio Unit hosting for additional
processors. [Effects documentation](https://www.rogueamoeba.com/support/knowledgebase/?product=Audio+Hijack&showArticle=AboutEffects).

## Loopback

Loopback creates system-visible virtual devices. Users can combine application
and hardware sources, set levels, and map channels. Its Pass-Thru source makes
a virtual device writable as an output as well as readable as an input.
[Sources](https://rogueamoeba.com/support/manuals/loopback/?page=sources),
[pass-through](https://rogueamoeba.com/support/manuals/loopback/?page=passthru).

The documented microphone-enhancement workflow uses Audio Hijack for effects
and Loopback for transport into a calling app. This is ClearMic's initial use
case. [Microphone enhancement guide](https://www.rogueamoeba.com/support/knowledgebase/?product=Audio+Hijack&showArticle=Misc-ApplyingMicEffects).

## An open-source implementation

BlackHole provides a GPLv3 AudioServerPlugIn driver, including configurable
device names and separate visible-input/hidden-output mirror devices. It
documents UID lookup of hidden devices and app integration under GPLv3.
ClearMic uses this supported configuration with upstream source pinned to
v0.7.2. [Upstream documentation](https://github.com/ExistentialAudio/BlackHole).

Apple's AudioDeviceIOProc receives input and output buffers on the audio I/O
cycle. Core Audio aggregate devices align independent device clocks, and drift
correction resamples unsynchronised devices. These APIs support the selected
interface-to-driver bridge without a custom asynchronous sample-rate converter.
[IO callback](https://developer.apple.com/documentation/coreaudio/audiodeviceioproc),
[aggregate clocks](https://developer.apple.com/documentation/coreaudio/audiohardwareaggregatedevice),
[drift correction](https://support.apple.com/guide/audio-midi-setup/ams094c7edb4/mac).

RØDE's XLR output is analogue; USB exposes its device configuration and onboard
processing. ClearMic applies a new processing chain downstream of the interface.
[RØDE connection explanation](https://help.rode.com/hc/en-us/articles/16702089296783-Why-Won-t-R%C3%98DE-Software-Detect-My-XLR-Connected-R%C3%98DE-Microphone).

## Scope

ClearMic implements a single selected mic channel, fixed voice processors and
one virtual input. Multi-source mixing, application capture, routing matrices,
plug-in hosting, file recording and broadcasts are separate capabilities that
the reference products support. They have not been implemented or verified here.
