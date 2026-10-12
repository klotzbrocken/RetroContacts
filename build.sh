#!/bin/bash
# Baut RetroContacts.app (universal arm64+x86_64, macOS 14+). Standard: ad-hoc signiert für lokale Tests.
# SIGN_ID="Developer ID Application: …" ./build.sh  -> mit Hardened Runtime und Zeitstempel signieren.
set -e
cd "$(dirname "$0")"
APP=RetroContacts.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build-tmp
if [ ! -f Resources/AppIcon.icns ]; then
  S=$(mktemp -d)/AppIcon.iconset; mkdir -p "$S"
  for sz in 16 32 128 256 512; do
    sips -z $sz $sz Resources/icon-source.png --out "$S/icon_${sz}x${sz}.png" >/dev/null
    sips -z $((sz*2)) $((sz*2)) Resources/icon-source.png --out "$S/icon_${sz}x${sz}@2x.png" >/dev/null
  done
  iconutil -c icns "$S" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $ARCH-apple-macos14.0 -o .build-tmp/RetroContacts-$ARCH \
    -framework Cocoa -framework Contacts Sources/*.swift 2>&1 | grep -E "error" || true
done
lipo -create .build-tmp/RetroContacts-arm64 .build-tmp/RetroContacts-x86_64 -output "$APP/Contents/MacOS/RetroContacts"
rm -rf .build-tmp
if [ -n "$SIGN_ID" ]; then
  codesign --force --options runtime --timestamp --entitlements RetroContacts.entitlements --sign "$SIGN_ID" "$APP"
else
  codesign --force --sign - --entitlements RetroContacts.entitlements "$APP"
fi
codesign --verify --strict --verbose=1 "$APP" 2>&1 | tail -1
echo "OK: $PWD/$APP"
