#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/dist/ModuleCache"
ARCH="$(uname -m)"
xcrun swiftc -swift-version 5 -target "$ARCH-apple-macosx13.0" \
    -module-cache-path "$ROOT/dist/ModuleCache" \
    "$ROOT/Sources/Core.swift" "$ROOT/Sources/BrowserRegistration.swift" "$ROOT/Sources/App.swift" "$ROOT/Tests/CoreTests.swift" \
    -framework AppKit -framework SwiftUI -o "$ROOT/dist/CoreTests"
"$ROOT/dist/CoreTests"
