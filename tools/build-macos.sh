#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/output/connect/macos"
APP="$BUILD/eXTMonitor.app"
EXT="$APP/Contents/PlugIns/DDMMWidget.appex"
SIGNING_IDENTITY=${EXTMONITOR_SIGNING_IDENTITY:--}
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -O -framework AppKit -framework SwiftUI -framework WidgetKit "$ROOT/macos/Shared.swift" "$ROOT/macos/AudioRouter.swift" "$ROOT/macos/Controller.swift" "$ROOT/macos/main.swift" -o "$APP/Contents/MacOS/DDMMConnect"
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -O -parse-as-library -application-extension -framework SwiftUI -framework WidgetKit "$ROOT/macos/Shared.swift" "$ROOT/macos/Widget.swift" -o "$EXT/Contents/MacOS/DDMMWidget"
cp "$ROOT/macos/bridge.py" "$APP/Contents/Resources/bridge.py"
python3 "$ROOT/tools/macos-bundle.py" "$APP"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --entitlements "$ROOT/macos/widget.entitlements" "$EXT"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --entitlements "$ROOT/macos/app.entitlements" "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
echo "$APP"
