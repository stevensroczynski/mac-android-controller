#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" != "--no-build" ]; then
    if [ "$#" -ne 0 ]; then echo 'Usage: install-app.sh [--no-build]' >&2; exit 1; fi
    ./scripts/build-app.sh
fi
APP=dist/Glide.app
APPLICATIONS_DIR="${UCA_APPLICATIONS_DIR:-/Applications}"
DESTINATION="$APPLICATIONS_DIR/Glide.app"
IDENTIFIER=org.openinput.UniversalControlAndroid
codesign --verify --deep --strict "$APP"
if [ -e "$DESTINATION" ]; then
    EXISTING_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)
    if [ "$EXISTING_ID" != "$IDENTIFIER" ]; then
        echo 'A different Glide app already exists at the destination; refusing to replace it.' >&2
        exit 1
    fi
fi
mkdir -p "$APPLICATIONS_DIR"
STAGING=$(mktemp -d "$APPLICATIONS_DIR/.glide-install.XXXXXX")
INSTALLED=false
cleanup() {
    if [ "$INSTALLED" = false ] && [ -e "$STAGING/previous.app" ]; then
        if [ -e "$DESTINATION" ]; then mv "$DESTINATION" "$STAGING/failed.app"; fi
        mv "$STAGING/previous.app" "$DESTINATION"
    fi
    rm -rf "$STAGING"
}
trap cleanup EXIT
ditto "$APP" "$STAGING/Glide.app"
codesign --verify --deep --strict "$STAGING/Glide.app"
# Stop the previous build before replacing its bundle; this also releases input.
pkill -TERM -x UniversalControlAndroid || true
for attempt in {1..50}; do
    if ! pgrep -x UniversalControlAndroid >/dev/null; then break; fi
    sleep 0.1
done
if pgrep -x UniversalControlAndroid >/dev/null; then
    echo 'Glide is still running. Quit it before installing.' >&2
    exit 1
fi
if [ -e "$DESTINATION" ]; then mv "$DESTINATION" "$STAGING/previous.app"; fi
mv "$STAGING/Glide.app" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
INSTALLED=true
open "$DESTINATION"
echo "Installed and opened $DESTINATION"
