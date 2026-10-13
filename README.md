# Universal Control for macOS and Android

A native macOS menu-bar app that shares mouse and keyboard input with an Android
phone over USB using Android HID input. The phone keeps its own screen. No video, audio, accounts, cloud,
telemetry, or clipboard synchronization.

**Status: experimental USB preview.** Read [validation](docs/VALIDATION.md) before
relying on it. Automatic return uses a small Android Accessibility companion;
turning that option off leaves an explicitly incomplete manual-return mode.
Wi-Fi is not implemented. This is not an Apple product.

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
4. Select the phone. Enter its 32-character companion code. That code is kept only
   in memory on the Mac; it is stored in private app preferences on Android.
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
- Actual hover detection at the Android edge, adjustable Mac crossing region,
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
- No Wi-Fi, clipboard, file transfer, login item, or latency guarantee in this version.

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
