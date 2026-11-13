#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
APP="$DIST/DFBrowser-$VERSION.app"
MACOS="$APP/Contents/MacOS"
ARCH="$(uname -m)"
SDK="$(xcrun --show-sdk-path)"
mkdir -p "$MACOS" "$APP/Contents/Resources" "$DIST/ModuleCache"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/DFBrowser.icns" "$APP/Contents/Resources/DFBrowser.icns"
xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macosx13.0" \
    -sdk "$SDK" -module-cache-path "$DIST/ModuleCache" \
    "$ROOT/Sources/Core.swift" "$ROOT/Sources/BrowserRegistration.swift" "$ROOT/Sources/App.swift" "$ROOT/Sources/main.swift" \
    -framework AppKit -framework SwiftUI -o "$MACOS/DFBrowser"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
/usr/bin/ditto -c -k --keepParent "$APP" "$DIST/DFBrowser-$VERSION-macOS-$ARCH.zip"
printf 'Built %s\n' "$APP"
