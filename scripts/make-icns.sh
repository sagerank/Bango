#!/usr/bin/env bash
# Builds assets/AppIcon.icns from assets/icon-1024.png using tools that ship with macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="assets/icon-1024.png"
OUTPUT="assets/AppIcon.icns"
[ -f "$SOURCE" ] || { echo "Missing $SOURCE" >&2; exit 1; }

SET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE" --out "$SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$OUTPUT"
rm -rf "$(dirname "$SET")"
echo "Wrote $OUTPUT"
