#!/bin/bash
# Generates iOS + macOS app icons for Ethan Workbench from assets/icon/app_icon.png
# Usage: ./scripts/generate_icon.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_ICON="$ROOT_DIR/assets/icon/app_icon.png"
IOS_ICONSET="$ROOT_DIR/ios/Runner/Assets.xcassets/AppIcon.appiconset"
MAC_ICONSET="$ROOT_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$BASE_ICON" ]]; then
  echo "Missing base icon: $BASE_ICON" >&2
  exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick (magick) is required" >&2
  exit 1
fi

mkdir -p "$IOS_ICONSET" "$MAC_ICONSET"

echo "Generating iOS app icons from $BASE_ICON..."
magick "$BASE_ICON" -resize 1024x1024 "$IOS_ICONSET/Icon-App-1024x1024@1x.png"
magick "$BASE_ICON" -resize 20x20   "$IOS_ICONSET/Icon-App-20x20@1x.png"
magick "$BASE_ICON" -resize 40x40   "$IOS_ICONSET/Icon-App-20x20@2x.png"
magick "$BASE_ICON" -resize 60x60   "$IOS_ICONSET/Icon-App-20x20@3x.png"
magick "$BASE_ICON" -resize 29x29   "$IOS_ICONSET/Icon-App-29x29@1x.png"
magick "$BASE_ICON" -resize 58x58   "$IOS_ICONSET/Icon-App-29x29@2x.png"
magick "$BASE_ICON" -resize 87x87   "$IOS_ICONSET/Icon-App-29x29@3x.png"
magick "$BASE_ICON" -resize 40x40   "$IOS_ICONSET/Icon-App-40x40@1x.png"
magick "$BASE_ICON" -resize 80x80   "$IOS_ICONSET/Icon-App-40x40@2x.png"
magick "$BASE_ICON" -resize 120x120 "$IOS_ICONSET/Icon-App-40x40@3x.png"
magick "$BASE_ICON" -resize 57x57   "$IOS_ICONSET/Icon-App-57x57@1x.png"
magick "$BASE_ICON" -resize 114x114 "$IOS_ICONSET/Icon-App-57x57@2x.png"
magick "$BASE_ICON" -resize 120x120 "$IOS_ICONSET/Icon-App-60x60@2x.png"
magick "$BASE_ICON" -resize 180x180 "$IOS_ICONSET/Icon-App-60x60@3x.png"
magick "$BASE_ICON" -resize 50x50   "$IOS_ICONSET/Icon-App-50x50@1x.png"
magick "$BASE_ICON" -resize 100x100 "$IOS_ICONSET/Icon-App-50x50@2x.png"
magick "$BASE_ICON" -resize 72x72   "$IOS_ICONSET/Icon-App-72x72@1x.png"
magick "$BASE_ICON" -resize 144x144 "$IOS_ICONSET/Icon-App-72x72@2x.png"
magick "$BASE_ICON" -resize 76x76   "$IOS_ICONSET/Icon-App-76x76@1x.png"
magick "$BASE_ICON" -resize 152x152 "$IOS_ICONSET/Icon-App-76x76@2x.png"
magick "$BASE_ICON" -resize 167x167 "$IOS_ICONSET/Icon-App-83.5x83.5@2x.png"

echo "Generating macOS app icons..."
magick "$BASE_ICON" -resize 16x16     "$MAC_ICONSET/app_icon_16.png"
magick "$BASE_ICON" -resize 32x32     "$MAC_ICONSET/app_icon_32.png"
magick "$BASE_ICON" -resize 64x64     "$MAC_ICONSET/app_icon_64.png"
magick "$BASE_ICON" -resize 128x128   "$MAC_ICONSET/app_icon_128.png"
magick "$BASE_ICON" -resize 256x256   "$MAC_ICONSET/app_icon_256.png"
magick "$BASE_ICON" -resize 512x512   "$MAC_ICONSET/app_icon_512.png"
magick "$BASE_ICON" -resize 1024x1024 "$MAC_ICONSET/app_icon_1024.png"

echo "All app icons generated successfully!"
echo "iOS: $IOS_ICONSET"
echo "macOS: $MAC_ICONSET"
