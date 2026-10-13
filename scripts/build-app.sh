#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
APP=dist/UniversalControlAndroid.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN_DIR/UniversalControlAndroid" "$APP/Contents/MacOS/"
USB_PREFIX=$(brew --prefix libusb)
if [ -f "$APP/Contents/Frameworks/libusb-1.0.0.dylib" ]; then
    chmod u+w "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
fi
cp "$USB_PREFIX/lib/libusb-1.0.0.dylib" "$APP/Contents/Frameworks/"
chmod u+w "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
install_name_tool -id '@rpath/libusb-1.0.0.dylib' "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
USB_LINK=$(otool -L "$APP/Contents/MacOS/UniversalControlAndroid" | awk '/libusb-1.0/{print $1}')
install_name_tool -change "$USB_LINK" '@executable_path/../Frameworks/libusb-1.0.0.dylib' "$APP/Contents/MacOS/UniversalControlAndroid"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
if [ ! -f dist/uca-hid.jar ]; then
    echo 'Build Android artifacts first: ./scripts/build-android.sh' >&2
    exit 1
fi
cp dist/uca-hid.jar "$APP/Contents/Resources/"
cp "$USB_PREFIX/COPYING" "$APP/Contents/Resources/libusb-LICENSE.txt"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.openinput.UniversalControlAndroid</string>
<key>CFBundleExecutable</key><string>UniversalControlAndroid</string>
<key>CFBundleName</key><string>UniversalControlAndroid</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (ad-hoc signed, not notarized)"
