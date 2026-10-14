# Universal Control for macOS and Android

A native macOS menu-bar app that shares mouse and keyboard input with an Android
phone over USB or paired Wi-Fi using Android HID input. Input-sharing mode keeps
Android on the phone. An experimental extended-display mode streams a separate
Mac desktop to the phone. No audio, accounts, cloud, telemetry, or clipboard sync.

**Status: experimental USB/Wi-Fi preview.** Read [validation](docs/VALIDATION.md) before
relying on it. Automatic return uses a small Android Accessibility companion;
turning that option off leaves an explicitly incomplete manual-return mode.
Wireless mode requires Android 11+ Wireless Debugging. This is not an Apple product.

## Experimental extended display

1. Install the updated Android companion and Mac app from this branch.
2. Open the **Extended Display** tab, unlock the phone, select it, and choose USB or paired Wi-Fi.
3. Choose a screen layout and click **Start display**. Allow macOS Screen Recording when prompted; quit and reopen
   the app if macOS requests it. Accessibility/Input Monitoring are not required
   for this mode because input stays native to macOS.
4. The companion viewer opens automatically. Drag a Mac window beyond the chosen
   desktop edge onto the phone. **Arrange displays…** opens macOS display settings.
5. Click **Stop display** on the Mac or **Close display** on Android.

This creates an extra desktop, not a mirror of the existing monitor. The phone
shows the captured Mac cursor; the Mac keyboard/mouse operate normally. Resolution
presets include **Fold 7 unfolded · Portrait** (984 × 1092) and **Landscape**
(1092 × 984), matching the inner screen at half resolution per dimension. The
viewer requests the selected orientation. Stop and restart to change layouts;
folding during a session still letterboxes. The pipeline prioritizes response time,
with low-latency encoding and no queue of frames waiting for Android decoding. There is no phone-touch-to-Mac control or audio in this preview. Use
the **Cursor Only** tab for Android input sharing after stopping extended-display mode.
Changing tabs by itself does not stop or start a session.

The Mac virtual-display adapter uses undocumented CoreGraphics interfaces, runtime
checked on startup. It may break on another macOS release and is not an App Store
implementation. Capture and H.264 encoding use ScreenCaptureKit and VideoToolbox;
the Android viewer uses MediaCodec. All video stays in memory and travels through
the selected authorized ADB connection (USB or TLS Wi-Fi). The viewer must remain
foreground. Screen lock, leaving the viewer, connection loss, Stop, Quit, or Mac
sleep stops streaming and removes the temporary display. See
[the implementation and validation notes](docs/EXTENDED_DISPLAY.md).

## Requirements

- macOS 13 or later, Swift 5.9+ and Command Line Tools (full Xcode is optional).
- An Android phone with authorized USB debugging and UHID support, or Android Open Accessory 2.0 HID, plus a USB data cable.
- Homebrew `libusb`; ADB for the edge companion. Android 9+ for the companion.
- Accessibility and Input Monitoring permissions for the Mac app.
- Android Accessibility service and authorized USB debugging for automatic return.

## Build the Mac app

Build the Android artifacts in the next section first; the Mac bundle includes
the locally built `uca-hid.jar` helper.

```sh
xcode-select --install # only if Command Line Tools are missing
brew install libusb
brew install --cask android-platform-tools
swift run CoreChecks
./scripts/build-app.sh
open dist/UniversalControlAndroid.app
```

The output is ad-hoc signed, **not Developer ID signed or notarized**. Build locally;
do not disable Gatekeeper or System Integrity Protection. The bundle includes
libusb; ADB is located in `/opt/homebrew/bin` or `/usr/local/bin` at runtime.
Build on the target architecture. Binary distribution is not part of the initial
source release.

## Build and install the Android companion

```sh
brew install openjdk@17
brew install --cask android-commandlinetools
export JAVA_HOME="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
sdkmanager "platforms;android-35" "build-tools;35.0.0"
./scripts/build-android.sh
adb -d install -r dist/AndroidEdgeReturn.apk
adb -d shell am start -n org.openinput.uca/.MainActivity
```

Review and accept the SDK license when prompted. Set `ANDROID_SDK_ROOT` and
`JAVA_HOME` to use existing installations. The script generates a local debug
signing key under the ignored `android/build` directory. Keep that key locally
for future APK updates. It is not a production signing credential.

1. Enable Developer options and USB debugging on Android. Connect by USB and
   authorize this Mac. Leave USB role selection alone if the phone is detected.
2. Open **Android Edge Return**, then enable its Accessibility service. For a
   restricted sideloaded app, use **App info → menu → Allow restricted settings**.
3. Open the Mac app. Grant Accessibility and Input Monitoring in System Settings,
   then quit and reopen it if required by macOS.
4. Select the phone and Connect. The updated companion supplies its code over
   authorized ADB; the Mac saves it in Keychain after authentication. Older
   companions can still use manual entry. Android stores it in private preferences.
5. Choose the Mac display and phone position (default: right). Click **Connect**.
6. Move into the Mac display interior, release all keys/buttons, then move through
   the configured edge region. Move the phone's cursor into the tinted return
   strip to hand control back.

The default emergency release is **Control + Option + Command + Escape**.
F12 can be selected instead of Escape. Disconnect and Quit also release input.
Crossings are suppressed at seams shared with another Mac display. Hold no keys
or mouse buttons during entry. After return, move at least 24 points inside the
Mac display to re-arm. The phone's pointer position is not estimated from deltas;
its native acceleration remains under Android's control.

## Features and limits

- Native relative mouse, five buttons, dragging, vertical and horizontal wheel
  reports, and fractional trackpad-scroll accumulation.
- USB physical-key keyboard reports, modifiers, arrows, Delete/Backspace, six-key
  rollover, and Android-controlled repeat. Set the **physical keyboard layout on
  Android** to match your keyboard; macOS IME composition is not transmitted.
- Matching entry and return positions across ten sections of the shared edge.
- Return to the Mac by holding the pointer at the outer edge for 450 ms;
  moving inward cancels the return. Adjustable Mac crossing region,
  four arrangements, and release on rotation/folding, sleep or transport failure.
- While Android owns input, system trackpad gestures are suppressed on the Mac.
  Complete a three-finger system swipe in any direction to open Android's recent
  apps overview. This follows the Mac's system-swipe configuration (four fingers
  if that is what macOS uses), requires the edge companion, and leaves two-finger
  scrolling on Android. Pinch/rotate are suppressed, not mapped.
  Gesture interception uses undocumented macOS event fields and needs physical
  testing after OS upgrades; it cannot guarantee suppression of every OS gesture.
- Back/Home/Recents buttons use the companion's public Accessibility actions.
- No automatic reconnection: explicitly select Connect after interruptions.
- The app tries AOA, then falls back to the bundled UHID helper over authorized
  USB ADB if the phone rejects AOA. AOA may conflict with another USB control program. Close scrcpy and other input-sharing tools before connecting.
- The companion's narrow edge strip receives input at that boundary. Cross-device
  drag-and-drop is not supported. Return during a held drag may require releasing
  the mouse button first. System gestures or protected screens can affect delivery.
- Reserved macOS shortcuts and Secure Input can prevent capture. Never treat
  capture as a system security boundary.
- Pointer placement on entry is not synchronized to the Mac's crossing height.
- No clipboard, file transfer, login item, or latency guarantee in this version.

## Tests and diagnostics

```sh
swift run CoreChecks
swift run UniversalControlAndroid --diagnose
```

Diagnostics print counts and permission state, never device serials or key data.
For an explicit hardware smoke test, first open the isolated Android test surface:

```sh
adb -d shell am start -n org.openinput.uca/.InputTestActivity
swift run UniversalControlAndroid --usb-smoke
```

This sends real movement, a click, scrolling, and the A key. **Keep the test
activity foreground and sharing disconnected while running it.** Its counters
record only events received by that activity and do not retain typed characters.
USB success alone does not prove application delivery; check the phone's counters.

See [architecture](docs/ARCHITECTURE.md), [security](SECURITY.md), and
[third-party notices](THIRD_PARTY_NOTICES.md). Licensed under Apache-2.0.

## Wireless connection (Android 11+)

1. Put the Mac and phone on the same Wi-Fi network. On Android, enable Developer
   options → Wireless debugging → Pair device with pairing code.
2. In the Mac app select **Wi-Fi**, expand **Pair Wi-Fi phone (first time)**, enter
   the pairing screen's IP:port and six-digit code, then select **Pair**.
3. Select the discovered Wi-Fi phone and **Connect**. Discovery refreshes every
   five seconds while disconnected. The updated companion supplies its code
   automatically. The USB cable is unnecessary.
4. Keep the companion Accessibility service enabled for automatic edge return and
   recent-app gestures. Input capture and the emergency release shortcut work as
   with USB. Connection loss releases Mac input; reconnect explicitly to resume.

Pairing is saved by ADB/Android, not by this app. To revoke it, forget this Mac in
Android's Wireless debugging settings. The app clears the six-digit code after
use. The companion code is saved in macOS Keychain after authentication. The connection uses Android's
TLS Wireless Debugging service for both UHID input and the companion channel; no
legacy `adb tcpip 5555` listener is enabled. Only `_adb-tls-connect._tcp` services
are offered. Discovery requires mDNS between devices; guest networks/client
isolation, VPNs or firewalls can prevent discovery. Android may disable Wireless
debugging or change its port when networks change: enable it again and Refresh.

Wireless diagnostics: `swift run UniversalControlAndroid --wireless-smoke` sends
real input and requires exactly one advertised wireless phone, already paired,
with the isolated InputTestActivity foreground and app sharing disconnected.

## Companion setup and staying awake

The Android Control Companion shows connection, Accessibility and Wireless
Debugging status, with settings shortcuts and a **Disconnect Mac** button.
Use **Match physical keyboard layout** while connected to select UCA Keyboard
and the layout matching your Mac. Android can select different physical layouts
for different typing languages; configure each one. For example, using a Spanish
physical layout with a U.S. Mac keyboard can turn `?` into `_`.
Android advertises itself automatically while Wireless Debugging is enabled; the
Mac refreshes discovery while disconnected and remembers USB/Wi-Fi selection.
Android still requires the user to enable debugging and approve first-time
pairing. The companion cannot silently enable it after Android turns it off.

**Keep screen awake while connected** is on by default. A small blue indicator
uses Android’s window keep-screen-on flag while the authenticated companion
session is alive, including while other Android apps are foreground. The service
also renews a bounded screen wake lock. Disconnect, heartbeat loss, service
shutdown or disabling the toggle releases it. A locked/noninteractive phone ends
the session; there is no automatic unlock, wake-up flag or permanent screen-timeout
change. Device policies can still enforce a lock.

The 32-character companion code is retrieved only by the already-authorized ADB
shell, never advertised over Wi-Fi. It is refreshed from the selected device on
each connection and cached in Keychain after authentication. **Forget saved
companion code** removes the Mac cache; the next connection retrieves it again.
Resetting the Android companion code disconnects the session but does not revoke
ADB authorization. To revoke a Mac, forget it in Android's Wireless Debugging
settings (and revoke USB debugging authorizations where applicable).
