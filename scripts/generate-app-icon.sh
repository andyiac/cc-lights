#!/usr/bin/env bash
# Regenerate Resources/AppIcon.icns from the 1024x1024 master Resources/AppIcon.png.
# The master PNG already has transparent rounded corners; this only resizes and packs.
set -euo pipefail

cd "$(dirname "$0")/.."

master="Resources/AppIcon.png"
iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"

if [[ ! -f "$master" ]]; then
  echo "Missing $master" >&2
  exit 1
fi

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$master" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size*2))" "$((size*2))" "$master" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$iconset" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
