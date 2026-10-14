# Validation report

Date: 2026-10-13. Status: experimental USB preview; full MVP acceptance is not yet complete.

## Executed

- macOS ARM64 debug and release builds: passed using Swift 6.1 and Command Line Tools.
- Native app packaging, bundled libusb and UHID helper, ad-hoc signature verification: passed.
- Android companion APK and public-API UHID helper compilation: passed.
- APK installation and Accessibility service enablement on a physical Android phone: verified during development; the final package requires the user to re-enable the service.
- `swift run CoreChecks`: twelve scenarios, 401 assertions passed. Covers all edges,
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

- Copy/paste and the Show code toggle: verified through the packaged Mac UI with
  a dummy value, followed by the supplied private code in the masked field.
- macOS Accessibility and Input Monitoring: verified for an earlier build; each
  rebuilt ad-hoc bundle may require fresh permission entries.
- GitHub CI: full core checks, Android compilation and Mac app packaging passed
  on [run 38415146988](https://github.com/stevensroczynski/mac-android-controller/actions/runs/38415146988).
- Source privacy audit: 32 source/configuration files reviewed; Gitleaks found
  no secrets in the complete two-commit history. Git uses a no-reply author email.

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
cleanup. Wi-Fi is implemented using TLS Wireless Debugging; physical wireless acceptance remains pending.

The app is ad-hoc signed. Rebuilding can invalidate macOS permission entries;
remove/re-add the new bundle in Accessibility and Input Monitoring, then restart.
Local artifacts are `dist/UniversalControlAndroid.app`, `dist/AndroidEdgeReturn.apk`,
and `dist/uca-hid.jar`. Artifacts and debug signing keys are ignored by Git.

## Trackpad gesture update

- Added session event interception for gesture/Dock-control events while Android
  owns input, and a completed system swipe sends the companion's RECENTS action.
- Core checks cover one action per swipe, Mac ownership, cancellation, release
  during a swipe, missing readiness, tiny movement and velocity-only completion.
- Debug compilation and core checks passed. Physical swipe suppression and
  Android overview activation remain pending; synthetic state tests do not prove
  delivery by the macOS trackpad driver.
- The gesture stream does not provide a supported finger-count contract. It
  follows the configured three/four-finger system swipe and uses undocumented
  event types 29/30 and fields 110/124/129/130/132, isolated in TrackpadGestures.

## Wireless update

- Added Wi-Fi discovery, first-time pairing UI and explicit wireless selection.
  Both UHID and edge/navigation channels use the selected ADB TLS service.
- Parser checks reject legacy TCP services, pairing services, malformed targets,
  invalid IP/ports and duplicates. Ten scenarios / 86 assertions passed, along
  with debug compilation. No private addresses or device IDs are test fixtures.
- A physical TLS advertisement was discovered. Pairing and actual wireless input
  delivery still need hardware verification; discovery alone is not acceptance.

## Wireless latency correction

- Found one synchronous network round trip per input report, with a 96-report
  queue that disconnected on overflow. Replaced with UCA2 bounded batches and
  adjacent mouse coalescing. Retained the 500 ms acknowledgment timeout, the
  three-second helper watchdog, ordered key/button events and emergency release.
- On the paired physical Wi-Fi device, 64 neutral mouse reports took 710 ms
  sequentially and 83 ms in batches of eight. A 15-second sustained batch check
  accepted 5,720 neutral reports with no disconnect. This measures transport
  throughput, not cursor latency, and does not validate edge-return stability.
- Core checks passed: 11 scenarios, 393 assertions, including movement sums,
  overflow without silent loss, batch bounds, click/key ordering and queue clear.
- Helper cleanup is asynchronous so an unreachable phone does not delay local
  failure recovery. The Mac bundles and pushes the new helper on connection;
  no companion APK reinstall is required.
- Real trackpad responsiveness and prolonged interactive Wi-Fi use still require
  user verification on the updated build.

## Companion setup update

- Android companion update built and installed while preserving app data.
  Accessibility remained enabled. Authorized shell credential retrieval passed.
- macOS Keychain save/read/delete verified using an isolated disposable test item.
- Core checks: 12 scenarios / 401 assertions, including strict credential-response
  parsing and rejection of malformed or multi-row responses.
- Authenticated connection while Android reported locked was closed as intended.
  On an unlocked phone, eight heartbeats and screen wake-lock renewal passed.
  After missing heartbeats, the protected status endpoint reported connected=0
  and awake=0. The phone subsequently returned to normal lock behavior.
- Mac UI restart/autofill and extended multi-app screen-awake behavior still need
  interactive verification. OS debugging enablement remains a user action.

- Companion watchdog timestamp is volatile across the socket and UI threads.
  Socket shutdown/close now runs outside the main looper so I/O cleanup cannot
  block the awake lease or its timeout callbacks. Historical entries in Android's
  power dump are not treated as evidence that a wake lock remains held.

## Ongoing Wi-Fi disconnect investigation

The user reported screen lock and rapid disconnects during actual use despite
short transport/lease checks passing. Those checks do not establish a stable
interactive session. Added a Mac user-initiated/latency-critical activity for the
entire sharing session (released on disconnect) to prevent App Nap timer deferral,
TCP_NODELAY for companion messages, and EINTR retry in acknowledgment polling.
Disconnect status now distinguishes input queue/acknowledgment failure, companion
heartbeat timeout/EOF and Android lock/heartbeat/host-close reasons.

A new `--wireless-session` diagnostic exercises both production channels together
at 120 neutral reports/second for 70 seconds, longer than the test phone's normal
30-second idle timeout. It requires an unlocked phone and a disconnected GUI.
The initial run reproduced phone lock and companion EOF. See the follow-up below
for the subsequent window-hold implementation and its extended test result.


## Screen window hold and keyboard layout follow-up

The extended Wi-Fi diagnostic reproduced a phone lock followed by companion EOF;
the protected status reported `phone_locked` with a recent heartbeat. The legacy
screen wake lock alone did not prevent the lock. Added a visible accessibility
window with FLAG_KEEP_SCREEN_ON, independent of the armed return strip, and a
physical-keyboard settings shortcut. The Mac used U.S. layout while Android's
layout manager included Spanish physical-layout selections, consistent with the
reported punctuation mismatch. No key-usage swap was applied: physical layouts
must match across devices. The updated companion was built and installed. A 70-second concurrent Wi-Fi
session passed with both production channels and 120 neutral mouse reports per
second, exceeding the phone's 30-second idle timeout. During the run Android
reported Awake and named the UCA indicator as its screen-holding window; the
companion reported connected=1 and awake=1. The active UCA Keyboard overlay was
confirmed as Latin American Spanish, mismatching the Mac's U.S. layout. Changing
the physical layout and checking actual punctuation remain user verification;
this transport test does not establish all-day stability or typing correctness.
CoreChecks passed 12 scenarios / 401 assertions.

After diagnostic disconnect, the companion reported connected=0 / awake=0 and
Android reported no screen-holding window on either display. The Mac app was
reopened without rebuilding its binary or changing its permission identity.


## Deliberate edge return

Replaced immediate return on hover with a 450ms dwell inside the outermost 2dp
of the selected edge. The existing 450ms post-arm cooldown remains. Hover exit,
inward motion, disarm, disconnect, rotation and strip replacement cancel pending
return callbacks. The strip brightens while return is pending. Android build and
APK signature verification passed; the updated companion was installed. Physical
feel and dwell/cancel behavior still require user verification with the cursor.


## Ten-section cursor alignment

CoreChecks passed 13 scenarios / 563 assertions, including all ten sections on
all four edges and displays with negative origins. Android build/signature checks
passed. A live `--alignment-check` run over paired Wi-Fi passed 12 entry/return
round trips (sections 0, 5, 9 on all four edges). Each test positioned the real
UHID cursor using hover feedback, waited beyond the post-arm cooldown, moved to
the return boundary, and checked the section reported after the edge dwell. No
clicks or keys were sent. An initial first-frame race was reproduced and fixed by
waiting 150ms before probing the new hover surface. The temporary overlay is
removed on success, timeout, disarm, rotation, disconnect or replacement.

This verifies physical Android positioning and section return messages. The Mac
landing geometry is covered by CoreChecks; subjective everyday crossing feel,
rotation/folding during alignment and other device models remain user validation.
