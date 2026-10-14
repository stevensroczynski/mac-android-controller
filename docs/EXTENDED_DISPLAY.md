# Extended-display preview

## Design

The normal input-sharing path remains independent. Extended-display startup stops
input sharing and leaves all keyboard/mouse handling to macOS. A separate virtual
monitor extends the desktop, placed outside the existing display arrangement on
the chosen side. The new monitor is configured only for this login session. macOS
may choose a logical scaling different from the video pixel resolution.

`CVirtualDisplay` is a small Objective-C adapter around undocumented CoreGraphics
classes. Class availability, dimensions, initialization and mode application are
checked; exceptions return an unavailable result. The object is retained for the
session and released on stop. No driver, root helper, SIP change, persistent display
profile or system extension is installed. This approach is experimental across OS
versions and unsuitable for an App Store release.

`ExtendedDisplay` retrieves credentials from the selected authorized phone, starts
its viewer and waits for its listening state, creates a localhost ADB forward, then creates and captures only its own
new display ID. A generation token protects async startup against cancellation.
Failures remove the forward and display. The UI includes Start/Stop, three bounded
resolution presets and the system display arrangement shortcut.

`DisplayStream` uses ScreenCaptureKit with cursor capture, 30-fps target, three
capture surfaces, and VideoToolbox H.264 Baseline with no frame reordering and a
6-Mbit/s target. A serial queue owns capture/encoder/connection state. At most one
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
- Viewer replies one zero byte after enqueueing the access unit (or reading a
  heartbeat). This acknowledgment is flow control, not proof that a frame rendered.
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
reconnection without user action. Rotation/folding fits the existing stream with
letterboxing; select another resolution and restart if needed. Desktop windows
return to remaining Mac screens when the virtual display is removed. Protected
content may be blanked by the operating system. A new ad-hoc build can require
refreshing macOS permissions. Test longer sessions and the actual window workflow
before relying on it for work.
