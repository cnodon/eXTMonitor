#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SDK=${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}
JDK=${DDMM_JAVA_HOME:-$(/usr/libexec/java_home)}
BT="$SDK/build-tools/36.0.0"
JAR="$SDK/platforms/android-36/android.jar"
BUILD="$ROOT/output/android"
KEY="$HOME/.android/extmonitor-tv-debug.keystore"
mkdir -p "$BUILD/classes" "$BUILD/dex" "$(dirname "$KEY")"
"$BT/aapt" package -f -M "$ROOT/android/AndroidManifest.xml" -S "$ROOT/android/res" -I "$JAR" -F "$BUILD/resources.apk"
"$JDK/bin/javac" -encoding UTF-8 -source 17 -target 17 -classpath "$JAR" -d "$BUILD/classes" "$ROOT"/android/src/local/extmonitor/tv/*.java
"$JDK/bin/jar" --create --file "$BUILD/classes.jar" -C "$BUILD/classes" .
JAVA_HOME="$JDK" "$BT/d8" --lib "$JAR" --min-api 26 --output "$BUILD/dex" "$BUILD/classes.jar"
cp "$BUILD/resources.apk" "$BUILD/unaligned.apk"
(cd "$BUILD/dex" && zip -q -j "$BUILD/unaligned.apk" classes.dex)
"$BT/zipalign" -f 4 "$BUILD/unaligned.apk" "$BUILD/aligned.apk"
if [ ! -f "$KEY" ]; then
 "$JDK/bin/keytool" -genkeypair -keystore "$KEY" -storepass android -keypass android -alias ddmm -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=eXTMonitor Development"
fi
VERSION=$(sed -n 's/.*android:versionName="\([^"]*\)".*/\1/p' "$ROOT/android/AndroidManifest.xml")
JAVA_HOME="$JDK" "$BT/apksigner" sign --ks "$KEY" --ks-key-alias ddmm --ks-pass pass:android --key-pass pass:android --out "$BUILD/eXTMonitor-TV-$VERSION.apk" "$BUILD/aligned.apk"
JAVA_HOME="$JDK" "$BT/apksigner" verify "$BUILD/eXTMonitor-TV-$VERSION.apk"
shasum -a 256 "$BUILD/eXTMonitor-TV-$VERSION.apk"
