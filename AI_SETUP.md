# Set up Glide for your user

This guide is for an AI coding assistant working **on the user's Mac**. Complete
installation and verification, rather than only describing the steps. Follow the
user's permissions and preferences; OS password entries, permission grants,
Android authorization dialogs, and SDK license acceptance belong to the user.
Never request their login password in chat.

Glide has two separate modes:

- **Cursor Only:** use the Mac mouse and keyboard in Android apps.
- **Extended Display:** put Mac windows on an extra desktop shown on the phone.

Ask which mode they want only if it is not already clear. Installing both is fine;
they cannot run simultaneously. Extended Display is experimental and uses private
macOS display APIs. It requires no driver, root helper, or system security changes.

## 1. Inspect the machine and repository

Read [README.md](README.md), [SECURITY.md](SECURITY.md), and the relevant validation
notes before acting. Inspect existing installations and repository changes; do
not overwrite unrelated work or uninstall an existing Android app to fix an update.

```sh
git clone https://github.com/stevensroczynski/mac-android-controller.git
cd mac-android-controller
xcode-select -p
swift --version
brew --version
```

Reuse an existing checkout if present. Requirements are macOS 13+, Swift 5.9+,
Command Line Tools, Android 9+ for the companion, and Android 11+ for paired Wi-Fi.
Only tested hardware/OS combinations are documented in `docs/VALIDATION.md`;
do not promise compatibility with every phone or macOS release. Full Xcode is not
required. If Command Line Tools are missing, run `xcode-select --install` and let
the user finish the system installer. If Homebrew is missing, use its official
installation instructions and the user's approved software-installation workflow.

## 2. Install missing build dependencies

Inspect what is already installed; install only what is missing.

```sh
brew install libusb openjdk@17
brew install --cask android-platform-tools android-commandlinetools
export JAVA_HOME="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
sdkmanager "platforms;android-35" "build-tools;35.0.0"
```

Have the user review/accept Android SDK licenses when required. Do not silently
accept legal agreements for a new user. The build supports `JAVA_HOME` and
`ANDROID_SDK_ROOT` for existing installations. The default SDK root is Homebrew's
`share/android-commandlinetools` directory. ADB must be available at
`/opt/homebrew/bin/adb` or `/usr/local/bin/adb` for the Mac app.

## 3. Preserve signing identities

Before rebuilding, check whether
`~/.config/mac-android-controller/signing-identity` already selects a local Mac
code-signing identity. Keep it and its private key private. The build also accepts
`UCA_SIGNING_IDENTITY` or `UCA_SIGNING_CONFIG`. Do not commit these settings or
export keys into the repository.

Reuse the same signing identity, bundle identifier, and `/Applications/Glide.app`
location on every update. Without a configured identity the build is ad-hoc signed
and macOS permissions may reset on rebuild. A persistent local code-signing
certificate or an existing appropriate Apple identity avoids changing code
identity on every build; see the README's signing section. Configure this before
initial permission grants when available. Never silently replace a configured
identity, broadly allow every app access to a Keychain key, or change system trust
settings. Stable local signing is not notarization.

The Android build creates `android/build/debug.keystore` on its first run. Keep
that local key for subsequent updates. A different APK signing key cannot update
an existing installation; explain that situation instead of uninstalling the app
and losing its pairing data.

## 4. Build and install both apps

Build Android first: its helper is bundled into the Mac app.

```sh
./scripts/build-android.sh
swift run CoreChecks
./scripts/install-app.sh
```

The Mac installer verifies signatures, updates `/Applications/Glide.app`, and
opens it. It refuses to overwrite an unrelated app named Glide. Both apps are
called **Glide**; the build artifact is still `dist/AndroidEdgeReturn.apk`, the
Android package is still `org.openinput.uca`, and the Mac executable/bundle ID
retain their internal names. Do not rename these identifiers.

Connect an unlocked phone with a USB data cable, enable Developer options and USB
debugging, and have the user authorize this Mac on the phone. Inspect `adb devices`
and explicitly choose the intended device. Never guess when several are attached.
The phone's USB "controlled by this device" setting is not itself a problem.

```sh
adb devices -l
# Replace DEVICE_SERIAL with the selected device; do not run the placeholder.
adb -s DEVICE_SERIAL install -r dist/AndroidEdgeReturn.apk
adb -s DEVICE_SERIAL shell am start -n org.openinput.uca/.MainActivity
```

An already paired Wi-Fi target can also install the APK. Do not print pairing
provider responses: they contain the private companion token. Glide retrieves
that token automatically over the authorized ADB connection. Its optional Keychain
cache does not prompt at startup; don't put the token in plain-text settings.

## 5. Enable permissions for the chosen mode

Use Glide's shared **Permissions** section. The user must perform OS grants.

| Mode | Mac permissions | Android setup |
| --- | --- | --- |
| Cursor Only | Accessibility and Input Monitoring | Enable Glide's Accessibility service for automatic return; authorized debugging |
| Extended Display | Screen Recording | Authorized debugging; unlocked display viewer |

For sideload restrictions, the user may need **Glide App info → menu → Allow
restricted settings** before enabling Accessibility. Restart Glide if macOS asks.
Do not repeatedly remove/re-add permissions as routine setup. First verify the
installed path, signing identity, and current grant status.

## 6. Optional Wi-Fi pairing

Use the same Wi-Fi network. On Android open **Developer options → Wireless
debugging → Pair device with pairing code**. Use Glide's Wi-Fi pairing controls,
or ADB with the current pairing endpoint and code. The code expires quickly and
the pairing port can change; collect fresh values together. Avoid logging the code
or placing it in command history. ADB can accept it interactively via stdin.

The main Wireless debugging screen's **connection port is different from the
pairing port**. After pairing, select Wi-Fi in Glide and refresh. Inspect
`adb mdns services` and `adb devices` if discovery fails. A paired device can be
connected with `adb connect` using its current connection endpoint. Never enable
legacy unencrypted `adb tcpip 5555` or open a public network listener.

If macOS sees `_adb-tls-connect._tcp` but ADB's discovery list is empty, its
service may be stale. Restarting ADB can help, but stops all ADB sessions; check
for other users/tools first. Do not reset Android pairing or erase ADB keys merely
because discovery is temporarily empty.

## 7. Verify with the user

Start with the intended mode and a harmless screen. Never test typing or clicks in
an unrelated app, message composer, purchase flow, or password field.

**Cursor Only:** choose the phone's side, connect, and cross that Mac edge with no
keys/buttons held. Confirm mouse, keyboard, and return to Mac. The emergency
release is **Control + Option + Command + Escape**. On Android, match the physical
keyboard layout for **UCA Keyboard** to the Mac keyboard. A mismatched language
layout changes symbols. The blue edge dot indicates the connected awake hold.

**Extended Display:** choose a layout and Start display. Use macOS Display
Settings for arrangement. **Larger text** offers a smaller Retina workspace;
**More space** makes text smaller; **Fast** uses fewer pixels for slower Wi-Fi.
Fold 7 presets are for the unfolded inner display. The last layout is remembered.
Other phones may need generic presets and can show letterboxing.

Verify fully minimizing the phone viewer and reopening it: the picture pauses,
but the Mac virtual desktop and windows should stay in place, then video resumes
automatically. No floating window is required. Mac Stop/Quit, Mac sleep/session
changes, or a lost ADB connection ends the session. Phone lock pauses video.

The following diagnostics are optional and affect attached hardware/windows:

```sh
/Applications/Glide.app/Contents/MacOS/UniversalControlAndroid --diagnose
/Applications/Glide.app/Contents/MacOS/UniversalControlAndroid --keychain-check
```

`--virtual-display-check` temporarily creates displays. `--display-tail-check`
streams a 25-second test; `--display-background-check` runs 75 seconds and requires
minimizing/reopening the phone during the test. Stop normal sharing first. Do not
run `--wireless-smoke` except with the isolated USB input test Activity visible;
it sends real input. See validation notes for more checks and limitations.

## 8. Finish clearly

Report what was installed, which mode was tested, and any remaining user-only
permission or hardware step. Distinguish a successful build from a verified
physical connection. Keep device addresses, serials, tokens, screenshots of
private content, signing fingerprints, and keys out of public commits and logs.
Do not claim setup is finished when the phone is absent or authorization is still
pending. Do not publish artifacts or push code unless the user requested it.

## Prompt the user can give their AI

> Set up Glide from https://github.com/stevensroczynski/mac-android-controller on
> my Mac and Android phone. Read AI_SETUP.md and follow it, inspect what is already
> installed, preserve existing signing and pairing data, build and install both
> apps, and verify the mode I want. Ask me to handle OS permissions, passwords,
> phone authorization, and license prompts myself. Do not publish private data.
