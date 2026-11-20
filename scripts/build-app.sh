#!/bin/zsh
# Builds AskNicely.app (needed so macOS grants Bluetooth permission via Info.plist).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)

APP=build/AskNicely.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/AskNicely" "$APP/Contents/MacOS/"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp scripts/icon/AppIcon.icns "$APP/Contents/Resources/"
cp -R "$BIN"/AskNicely_AskNicely.bundle "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
(cd build && rm -f AskNicely.zip && ditto -c -k --keepParent AskNicely.app AskNicely.zip)
echo "Built $APP and build/AskNicely.zip"
echo "Run:  open $APP            (add --args --demo to force the prompt)"
