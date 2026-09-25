#!/bin/bash
# Regenerates Bundle/AppIcon.icns and docs/icon.png from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

swift scripts/make-icon.swift "$work/icon.png" >/dev/null
iconset="$work/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$work/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$work/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Bundle/AppIcon.icns
sips -z 256 256 "$work/icon.png" --out docs/icon.png >/dev/null
echo "Bundle/AppIcon.icns"
