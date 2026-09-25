#!/bin/bash
# Builds dist/ccid.app: the menu bar app, with the `ccid` command line tool inside it.
#   scripts/build-app.sh              build for this Mac
#   UNIVERSAL=1 scripts/build-app.sh  build for Apple silicon and Intel
set -euo pipefail
cd "$(dirname "$0")/.."

arch=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then arch=(--arch arm64 --arch x86_64); fi
swift build -c release ${arch[@]+"${arch[@]}"}
bin="$(swift build -c release ${arch[@]+"${arch[@]}"} --show-bin-path)"

app="dist/ccid.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp "$bin/CCIDApp" "$app/Contents/MacOS/ccid"
cp "$bin/ccid" "$app/Contents/Helpers/ccid"
cp Bundle/Info.plist "$app/Contents/Info.plist"
cp Bundle/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -R Bundle/en.lproj Bundle/zh-Hans.lproj "$app/Contents/Resources/"
plutil -lint "$app/Contents/Info.plist" >/dev/null

# Ad-hoc signature. Downloaded copies need one approval in Privacy & Security, since there is no Developer ID.
codesign --force --sign - "$app/Contents/Helpers/ccid"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
echo "$app"
