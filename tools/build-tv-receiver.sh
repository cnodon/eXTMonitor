#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE="$ROOT/output/connect/sources/OpenDisplay"
COMMIT=c023ef3e9dfed7497f89b47cd70d0aa420a59f30
SDK=${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}
JDK=${DDMM_JAVA_HOME:-$(/usr/libexec/java_home)}
KEY=${EXTMONITOR_TV_KEYSTORE:-$HOME/.android/ddmm-hometv-debug.keystore}
if [ ! -d "$SOURCE/.git" ]; then
  mkdir -p "$(dirname "$SOURCE")"
  git clone --depth 1 --branch v1.30.2 https://github.com/peetzweg/opendisplay.git "$SOURCE"
fi
[ "$(git -C "$SOURCE" rev-parse HEAD)" = "$COMMIT" ] || { echo 'Unexpected upstream commit' >&2; exit 1; }
if git -C "$SOURCE" apply --reverse --check "$ROOT/android/receiver/opendisplay-tv.patch" 2>/dev/null; then
  : # Patch already applied; never reset the checkout.
else
  git -C "$SOURCE" apply --check "$ROOT/android/receiver/opendisplay-tv.patch"
  git -C "$SOURCE" apply "$ROOT/android/receiver/opendisplay-tv.patch"
fi
JAVA_HOME="$JDK" ANDROID_HOME="$SDK" bash "$SOURCE/Android/gradlew" -p "$SOURCE/Android" assembleRelease testReleaseUnitTest -PappVersionName=1.30.2-ddmm.1 -PappVersionCode=1300201 --console=plain
[ -f "$KEY" ] || { echo 'Build HomeTV once to create the local development key.' >&2; exit 1; }
BT="$SDK/build-tools/36.0.0"
"$BT/zipalign" -f 4 "$SOURCE/Android/app/build/outputs/apk/release/app-release-unsigned.apk" "$ROOT/output/connect/DDMM-OpenDisplay-aligned.apk"
JAVA_HOME="$JDK" "$BT/apksigner" sign --ks "$KEY" --ks-key-alias ddmm --ks-pass pass:android --key-pass pass:android --out "$ROOT/output/connect/DDMM-OpenDisplay-1.30.2-ddmm.1.apk" "$ROOT/output/connect/DDMM-OpenDisplay-aligned.apk"
JAVA_HOME="$JDK" "$BT/apksigner" verify "$ROOT/output/connect/DDMM-OpenDisplay-1.30.2-ddmm.1.apk"
