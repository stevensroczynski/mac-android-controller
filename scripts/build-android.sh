#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_ROOT=${ANDROID_SDK_ROOT:-$(brew --prefix)/share/android-commandlinetools}
JAVA_ROOT=${JAVA_HOME:-$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home}
BUILD_TOOLS="$SDK_ROOT/build-tools/35.0.0"
ANDROID_JAR="$SDK_ROOT/platforms/android-35/android.jar"
export JAVA_HOME="$JAVA_ROOT"
export PATH="$JAVA_ROOT/bin:$PATH"
mkdir -p android/build/classes android/build/dex dist
"$BUILD_TOOLS/aapt2" compile --dir android/res -o android/build/resources.zip
"$BUILD_TOOLS/aapt2" link -o android/build/base.apk -I "$ANDROID_JAR" --manifest android/AndroidManifest.xml android/build/resources.zip
find android/src -name '*.java' > android/build/sources.txt
javac -source 8 -target 8 -Xlint:-options -classpath "$ANDROID_JAR" -d android/build/classes @android/build/sources.txt
jar cf android/build/classes.jar -C android/build/classes .
"$BUILD_TOOLS/d8" --lib "$ANDROID_JAR" --min-api 26 --output android/build/dex android/build/classes.jar
cp android/build/base.apk android/build/unsigned.apk
(cd android/build/dex && zip -q ../unsigned.apk classes.dex)
"$BUILD_TOOLS/zipalign" -f 4 android/build/unsigned.apk android/build/aligned.apk
# Local development key only. Never commit or distribute this keystore.
if [ ! -f android/build/debug.keystore ]; then
    keytool -genkeypair -keystore android/build/debug.keystore -storepass android -keypass android -alias androiddebugkey -dname 'CN=Android Debug' -keyalg RSA -validity 3650 >/dev/null 2>&1
    chmod 600 android/build/debug.keystore
fi
"$BUILD_TOOLS/apksigner" sign --ks android/build/debug.keystore --ks-pass pass:android --key-pass pass:android --out dist/AndroidEdgeReturn.apk android/build/aligned.apk
"$BUILD_TOOLS/apksigner" verify dist/AndroidEdgeReturn.apk
echo 'Built dist/AndroidEdgeReturn.apk (local debug signature)'
mkdir -p android/build/helper-classes android/build/helper-dex
find android/helper -name '*.java' > android/build/helper-sources.txt
javac -source 8 -target 8 -Xlint:-options -classpath "$ANDROID_JAR" -d android/build/helper-classes @android/build/helper-sources.txt
jar cf android/build/helper-classes.jar -C android/build/helper-classes .
"$BUILD_TOOLS/d8" --lib "$ANDROID_JAR" --min-api 28 --output android/build/helper-dex android/build/helper-classes.jar
jar cf dist/uca-hid.jar -C android/build/helper-dex classes.dex
echo 'Built dist/uca-hid.jar (authorized USB ADB helper)'
