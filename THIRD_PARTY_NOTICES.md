# Third-party notices

The application is licensed under Apache-2.0. Copyright 2026 Universal Control Android contributors.

## scrcpy research and HID descriptors

The standard HID mouse report layout and AOA request sequence were adapted with reference to
scrcpy (Genymobile, 2018–2026), Apache-2.0, revision
`a60891aea193d92e7e5c3942700eca63f9d19a5f`.
See <https://github.com/Genymobile/scrcpy>. The Apache license is in `LICENSE`.
This implementation uses a reduced keyboard descriptor without LED output and a separate
Swift input engine. No scrcpy executable or Android server is bundled or launched.

## libusb

The macOS application dynamically links libusb, LGPL-2.1-or-later.
Source and license: <https://github.com/libusb/libusb>.
The app packaging script copies the dylib and its license into the application bundle.
You may replace that library with a compatible build and ad-hoc re-sign the application.
No restriction on reverse engineering for debugging modifications to that library is imposed.
The initial build uses libusb 1.0.30, available from the upstream v1.0.30 tag.

## Development tools

Android SDK tools, platform APIs, JDK, Apple SDKs, and ADB remain under their respective
licenses. They are not bundled in the macOS application. The Android package contains
only this project's companion code and resources. DeskDockt was evaluated but no
DeskDockt code or legacy APK was incorporated.

## Trackpad gesture research

The undocumented macOS gesture event numbers and field meanings were researched
from [iss](https://github.com/joshuarli/iss) (0BSD). No iss executable, private
framework loader, or synthetic event implementation is bundled. The swipe
ownership and Android navigation logic are implemented here independently.
