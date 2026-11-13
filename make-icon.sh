#!/bin/bash
# Convert the preserved generated PNG to Apple's multi-resolution ICNS format.
# Does not install the icon or modify any running application.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$ROOT/Resources/DFBrowser-icon-original.png"
ICONSET="$ROOT/Resources/DFBrowser.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    /usr/bin/sips -z "$retina" "$retina" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$ROOT/Resources/DFBrowser.icns"
printf 'Created %s\n' "$ROOT/Resources/DFBrowser.icns"
