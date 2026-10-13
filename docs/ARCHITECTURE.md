# Architecture decision

## Evaluated implementations

Reviewed scrcpy `a60891aea193d92e7e5c3942700eca63f9d19a5f` and DeskDockt
`34b9e12b7ac60f9ed402a0c9702ebcc240616faf`.

| Concern | scrcpy | DeskDockt | Decision here |
|---|---|---|---|
| Functionality | Mature Android HID transports; no global edge handoff | Edge-sharing host and companion | Native host and small edge-only companion |
| macOS | Existing OTG/HID support | Python/Qt/Quartz host | AppKit menu and SwiftUI settings |
| Android | AOA USB or ADB UHID | Accessibility/IME companion | AOA or USB ADB UHID native cursor plus public Accessibility overlay |
| Latency | Direct HID reports | Custom protocol and companion input | Direct USB reports, bounded queue; measure separately |
| Stability | Established project | Younger cross-platform implementation | Small scope; hardware acceptance still essential |
| Security | Authorized local transports | Pairing and optional pinned TLS | USB only; random companion secret and no TCP phone listener |
| Complexity | Full client includes unnecessary media/window stack | Broader host, IME and transfer features | Reuse protocol/report design and libusb |
| License | Apache-2.0 | New code MIT; legacy binaries separate | Apache-2.0 app, dynamically linked LGPL libusb |
| Maintenance | Established upstream | Smaller project | No fork to maintain, but own host/companion tests required |

Sources:
- <https://github.com/Genymobile/scrcpy/blob/master/doc/otg.md>
- <https://github.com/Genymobile/scrcpy/blob/master/doc/control.md>
- <https://github.com/uncannyowly/DeskDockt/blob/main/wayland-host/COMPATIBILITY.md>
- <https://source.android.com/docs/core/interaction/accessories/aoa2>
- <https://developer.android.com/reference/android/view/WindowManager.LayoutParams#TYPE_ACCESSIBILITY_OVERLAY>

AOA HID is a documented Android accessory protocol. It requires no root, injected
Android server, hidden API, video encoding, or keyboard logging. USB requests 54–57
register descriptors, deliver reports, and unregister devices. Device discovery
checks the AOA protocol version before exposing a candidate to the user. Connection
rechecks the selected serial so a reused USB address cannot silently select a
different device. ADB uses that same serial for the companion channel.

## Components

- **ControlCore:** edge geometry, hysteresis, explicit input ownership, physical
  key mapping and standard HID report generation; no system capture or USB I/O.
- **CAccessory:** libusb discovery and AOA control requests. No interface seizure,
  accessory-mode switch, persistent device selection, or raw event logs.
- **USBTransport:** serial worker, 100 ms report timeout, bounded pending reports,
  cancellation generation, neutral reports on release, and a one-second USB probe.
- **Controller:** main-run-loop CGEventTap, display geometry, emergency shortcut,
  cursor visibility, permissions and session/sleep release. The event callback
  enqueues reports; it does not wait for USB or subprocesses.
- **EdgeLink:** authorized ADB forward to the phone's local abstract socket, random
  secret handshake, bounded lines, heartbeat and three-second timeout.
- **Android companion:** an Accessibility overlay confined to the return edge.
  Real mouse hover triggers RETURN. It does not retrieve windows, inspect other
  app text, inject input, use an IME, or request internet permission. Navigation
  uses documented Accessibility global actions. Configuration changes release.

## Handoff

Mac ownership starts unarmed. Motion through the interior arms the selected edge.
An outward crossing with no held keys/buttons requests Android ownership. The host
waits for the companion to acknowledge the overlay before forwarding input. The
phone cursor receives a small inward nudge, not a fabricated absolute coordinate.
The overlay ignores its first 450 ms to avoid immediate bounce. RETURN, emergency
release, sleep, failed transport or disconnection neutralizes reports, restores the
Mac cursor, and requires a fresh interior crossing after a 500 ms cooldown.

This is a practical hover-strip implementation, not Android-wide cursor telemetry.
OS overlays, foldable display behavior and held dragging need physical testing.
USB was prioritized; wireless HID remains deferred until USB acceptance is complete.

## Verified-device adjustment: USB ADB UHID

The physical test phone advertised AOA 2.0 but stalled HID registration (`LIBUSB_ERROR_PIPE`).
The app therefore also supports a small, locally compiled `uca-hid.jar` helper,
launched by an explicitly authorized USB ADB shell. It uses only public
`android.system.Os` operations and the documented Linux `/dev/uhid` interface.
It does not use scrcpy's injected-input APIs, Android reflection, or a media server.

The host pushes its bundled helper to a fresh path in `/data/local/tmp`, starts
`app_process` with fixed arguments over `adb shell -T` (duplex, no terminal), and
registers the same standard descriptors. Protocol UCA2 acknowledges each bounded batch (up to 64 reports) once.
The host drains a bounded 192-entry mailbox every 8 ms, merging adjacent mouse
reports only when button state and signed-axis limits permit. Keyboard/button
boundaries stay ordered; release clears pending reports. Single control frames
(heartbeat and neutralization) still receive individual acknowledgments. A one-second heartbeat keeps the helper alive. EOF or three seconds
without host traffic closes UHID file descriptors and automatically removes the
virtual devices. Normal stop removes the temporary helper; after a host crash its
inert JAR may remain in `/data/local/tmp` until manually removed. No input is stored
there. The host never connects a network ADB device automatically.

The Linux UHID structure layout follows <https://docs.kernel.org/hid/uhid.html>.
Kernel feature requests receive explicit unsupported replies. The helper has no
socket listener. Acknowledgment confirms kernel acceptance, not on-screen latency.

AOA remains a compatibility path. Unlike UHID, abrupt host termination may leave
AOA devices registered until USB is detached. Normal disconnect unregisters them.
Full crash resilience on the AOA path remains a known limitation.

## Wireless transport

Wireless selection discovers only Android's `_adb-tls-connect._tcp` mDNS services.
Pairing uses `adb pair` with the ephemeral six-digit code on stdin. A selected
wireless target bypasses AOA and runs the same UHID helper over the authenticated
TLS ADB shell. EdgeLink forwards its localhost socket over that same selected
transport. There is no automatic switch to another phone or from Wi-Fi to USB.
The existing report timeouts, bounded queue, neutralization and helper watchdog
apply on both transports. The historical USBTransport name now covers both.
Android's Wireless Debugging owns network listening and TLS; no custom network
listener or additional Android permissions are introduced.
