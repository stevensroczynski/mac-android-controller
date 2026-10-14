# Extended-display preview

## Design

The normal input-sharing path remains independent. Extended-display startup requires
input sharing to be stopped and leaves all keyboard/mouse handling to macOS. A separate virtual
monitor extends the desktop, placed outside the existing display arrangement on
the chosen side. The new monitor is configured only for this login session. macOS may choose a logical desktop size different from the video pixel resolution.
Each layout has a stable dimension-derived monitor identity so macOS does not
reuse another orientation’s preferences. No personal device identity is used.

`CVirtualDisplay` is a small Objective-C adapter around undocumented CoreGraphics
classes. Class availability, dimensions, initialization and mode application are
checked; exceptions return an unavailable result. The object is retained for the
session and released on stop. No driver, root helper, SIP change, persistent display
profile or system extension is installed. This approach is experimental across OS
versions and unsuitable for an App Store release.

`ExtendedDisplay` retrieves credentials from the selected authorized phone, starts
its viewer and waits for its listening state, creates a localhost ADB forward, then creates and captures only its own
new display ID. A generation token protects async startup against cancellation.
Failures remove the forward and display. Separate Cursor Only and Extended Display tabs expose the controls for each mode.
Changing tabs preserves the active session; starting the other mode requires
stopping the current one. Phone discovery pauses during an extended session.
Fold 7 unfolded presets are 984×1092 portrait and 1092×984 landscape, half of
[Samsung’s published inner-screen dimensions](https://news.samsung.com/global/samsung-galaxy-z-fold7-raising-the-bar-for-smartphones)
per axis. The viewer requests the chosen orientation. Generic 1280×800 and
1920×1080 presets remain available.

`DisplayStream` uses ScreenCaptureKit with cursor capture, 30-fps target, two
capture surfaces, and VideoToolbox H.264 Baseline with no frame reordering and a
4-Mbit/s target and Apple’s low-latency rate-control mode. Capture samples over
100 ms old are discarded before encoding. Encoder-dropped frames are skipped
without terminating the session. A serial queue owns capture/encoder/connection state. At most one
frame is encoding or awaiting a phone acknowledgment. Capture samples arriving
while busy are skipped before encoding, preserving inter-frame references. SPS/PPS
are prepended to keyframes; AVCC NAL units are converted to Annex B. No video is
written to disk. One-second heartbeat packets keep static desktops connected.
Encoder, socket and authentication waits are bounded; stalled sessions stop.

Android's `DisplayActivity` owns a foreground SurfaceView and local abstract socket.
It fits the video into the current phone dimensions without stretching. MediaCodec
consumes bounded Annex B access units and renders to the surface on a separate
output thread. Leaving the viewer closes the socket and blanks its surface; the
Mac removes the extra desktop when that close is observed. Activity generation
checks prevent a previous session's cleanup from stopping a newer session.

## Protocol

The authorized ADB client forwards an ephemeral localhost TCP port to
`localabstract:uca-display-v1` on the selected phone. No LAN listener or Android
INTERNET permission is added. Wi-Fi uses existing ADB TLS pairing.

- Client sends ASCII `AUTH ` followed by the existing 32-hex companion token and LF.
  The viewer compares it in constant time. Authentication lines are bounded at 64
  bytes and socket reads time out after five seconds.
- Viewer replies `OK` plus LF. Client sends `UCD1`, then unsigned big-endian 16-bit
  width and height. Width must be 640–2560 and height 480–2560.
- Each packet has a big-endian unsigned 32-bit payload length, big-endian unsigned
  64-bit presentation timestamp in microseconds, then an Annex B access unit.
  Payloads larger than 4 MiB and negative decoded timestamps are rejected. A zero
  length is a heartbeat and has no video payload.
- Viewer replies one zero byte after enqueueing an access unit (or reading a
  heartbeat). Android explicitly selects a decoder advertising low-latency
  support when available, and requests real-time priority. The decoder backlog
  is bounded at eight frames; if it reaches that ceiling, acknowledgments wait
  for output, with a two-second timeout. Allowing initial frames is necessary:
  waiting for the first output before sending frame two deadlocks some decoders.
  This acknowledgment is flow control, not proof of physical screen presentation.
- Shell-only `/display_status` reports connected/received/rendered counters and a bounded in-memory lifecycle
  trace of fixed event names without
  pixels, window titles, input content, credentials or device identifiers.

## Validation

- The virtual-display probe successfully created and released an active extra
  monitor on the development Mac. No physical display was selected for capture.
- The first 25-second USB animated-window test transmitted over 300 frames; Android
  independently reported over 300 decoded/rendered frames. The test window existed
  on the new virtual desktop. The display and forward were removed afterward.
- CoreChecks: 14 scenarios / 576 assertions, including NAL conversion, malformed
  lengths, packet bounds and heartbeat framing. Android builds and APK signature
  verification passed. A 25-second Wi-Fi animated-window test also passed, with 120 frames rendered by
  the phone. A subsequent USB reconnect streamed successfully. Opening the
  companion setup screen during that stream caused the Mac to stop; enumeration
  afterward showed zero temporary Android displays remaining.
- The final packaged USB check passed after receiver-readiness gating was added:
  the phone received 292 frames and rendered 287 during the 25-second test.
  Disconnect blanking uses a separate opaque cover, so hiding stale pixels does
  not race with SurfaceView recreation on the next session.
- The final packaged Wi-Fi reconnect from that same viewer session passed:
  120 frames received and 115 rendered over the 25-second check.
- Live receiver checks rejected a wrong token, invalid dimensions, and an
  oversized frame header before payload allocation. Three static-stream heartbeats
  were acknowledged. Each case reopened the viewer successfully.
- Android activity launch was corrected to CLEAR_TOP/SINGLE_TOP after reproducing
  a task-stack case where ordinary `am start` brought the setup screen forward
  instead of the existing display viewer.

## Current limits

This is a prototype, not a replacement for a production display driver. Target fps
is not a measured end-to-end latency guarantee. It has no audio, touch input back
to macOS, automatic video-resolution renegotiation on phone folding, HDR, or
reconnection without user action. The selected orientation is requested for the session; folding fits the existing
stream with letterboxing. Select another layout and restart if needed. Desktop windows
return to remaining Mac screens when the virtual display is removed. Protected
content may be blanked by the operating system. A new ad-hoc build can require
refreshing macOS permissions. Test longer sessions and the actual window workflow
before relying on it for work.

## Offline follow-up checks (2026-10-14)

- Core checks passed: 14 scenarios / 576 assertions.
- Four consecutive virtual-display create/release checks passed on the Mac,
  including both Fold orientations; logical desktop aspect ratios matched the
  requested video sizes within 0.005. macOS retained its own logical scaling.
- The actual Mac H.264 encoder emitted 20 individually submitted synthetic frames
  at each of the four preset sizes, without needing later frames to flush output.
  Mean encode times were 5.7–7.8 ms; these are synthetic encode-only timings,
  not end-to-end input latency measurements.
- This hardware encoder rejects the optional MaxFrameDelayCount setting in
  low-latency mode, so it is not set. Low-latency rate control, real-time encoding
  and disabled frame reordering are used instead.
- A subsequent physical Wi-Fi test found a startup deadlock with strict
  decoder-output acknowledgment: the phone needed additional frames before
  emitting its first output. The receiver now selects an explicitly low-latency
  decoder where available and permits bounded startup buffering.
- A 70-second physical concurrent Wi-Fi input/companion test passed with the
  screen-awake hold active after updating the stalled companion service.
- The corrected 25-second Wi-Fi display test passed: 146 frames received and
  145 rendered before shutdown, with no startup stall.
- Subjective cursor latency, both physical orientations and longer display
  sessions still need confirmation.

## Idle reconnect regression

An idle viewer could retain its abstract socket address after pause/rotation:
closing the listener alone did not reliably release a thread blocked in `accept`.
Receiver cleanup now shuts down the listener before closing it, and synchronizes
listener/client publication with cancellation so stale sessions cannot overwrite
new sockets. Input/output shutdown and close are attempted independently.

The on-device `python3 scripts/check-display-reconnect.py --run` regression passed
eight idle start/stop cycles alternating portrait and landscape over Wi-Fi. It
requires exactly one paired, unlocked phone and changes its foreground activity;
it sends no clicks, keystrokes or video. This covers the waiting-for-client path
that animated video tests did not exercise.

After those eight idle cycles, a full 25-second Wi-Fi display session passed
with 38 received and 37 rendered frames before intentional shutdown. This
confirms reconnect and delivery, not an end-to-end latency target.
