# Validation report

Date: 2026-10-13. Status: experimental USB preview; full MVP acceptance is not yet complete.

## Executed

- macOS ARM64 debug and release builds: passed using Swift 6.1 and Command Line Tools.
- Native app packaging, bundled libusb, ad-hoc signature verification: passed.
- Android companion APK and public-API UHID helper compilation: passed.
- APK installation and Accessibility service enablement on a physical Android phone: verified.
- `swift run CoreChecks`: seven scenarios, 38 assertions passed. Covers all edges,
  negative display origins, readiness, held buttons, crossing region, outward motion,
  cooldown/re-arm, single ownership, motion splitting, scrolling, key repeat state,
  rollover, key release, special keys, and left/right modifier mapping.
- Physical USB discovery and authorized ADB: verified.
- AOA HID registration: **failed**, despite advertised AOA 2.0 support; USB endpoint
  stalled with libusb error -9. This triggered the USB ADB UHID implementation.
- UHID registration and eight input transfers: passed.
- Actual Android delivery in the isolated input-test activity, while unlocked:
  **Hover 3, Clicks 1, Scroll 2, Key down 1, Key up 1**. Counters were read back
  from the test activity, not inferred from host writes. Earlier attempts while
  the device was locked did not reach that activity and are not counted as passes.
- The hardware test's roughly 400 ms total includes deliberate 50 ms delays.
  It is **not** an end-to-end latency measurement or a performance guarantee.

No device serials, pairing codes, private screenshots, or raw input logs are part
of this report or the source repository.

## Acceptance checklist

| Requirement | Evidence/status |
|---|---|
| Initial connection | Physical discovery, ADB authorization and UHID registration verified; GUI setup still under validation |
| Mac → Android automatic handoff | Implemented; physical event-tap/edge trial pending |
| Native Android control | Mouse, click, scroll and key delivery verified in isolated test activity |
| Android → Mac automatic handoff | Companion implemented; paired physical edge trial pending |
| Cable removal recovery | Implemented; physical unplug while captured pending |
| No mirroring | No video/audio transport or mirroring window exists in this application; developer used one local test screenshot for diagnosis |
| Repeated usage | Core hysteresis tested; repeated physical handoffs and stuck-key checks pending |

## Remaining checks

Verify on the physical device: normal left/right clicks and dragging, sustained
typing/repeat, international physical layout, four edges, lock/sleep, rotations,
folding/unfolding, multiple Mac displays, connection loss during capture, and app
crash recovery. Protected Android screens and system overlays may affect hover
delivery. AOA crash cleanup is a known limitation; USB ADB UHID has EOF and timeout
cleanup. Wi-Fi is intentionally unimplemented until USB acceptance is complete.

The app is ad-hoc signed. Rebuilding can invalidate macOS permission entries;
remove/re-add the new bundle in Accessibility and Input Monitoring, then restart.
Local artifacts are `dist/UniversalControlAndroid.app`, `dist/AndroidEdgeReturn.apk`,
and `dist/uca-hid.jar`. Artifacts and debug signing keys are ignored by Git.
