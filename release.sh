#!/bin/bash
# Signieren (Developer ID), DMG bauen, notarisieren, stapeln.
# Voraussetzung: einmalig `xcrun notarytool store-credentials "Retromac" --apple-id … --team-id …`
set -e
cd "$(dirname "$0")"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
SIGN_ID="${SIGN_ID:-Developer ID Application: Maik Klotz (FTJLR8JRNS)}"
PROFILE="${NOTARY_PROFILE:-Retromac}"
DMG="RetroContacts-$VERSION.dmg"
SIGN_ID="$SIGN_ID" ./build.sh
build/RetroContacts.app/Contents/MacOS/RetroContacts --selftest | tail -1
# 1) App notarisieren
ditto -c -k --keepParent build/RetroContacts.app RetroContacts-notarize.zip
xcrun notarytool submit RetroContacts-notarize.zip --keychain-profile "$PROFILE" --wait | tee /tmp/rc-notary-app.log
grep -q "status: Accepted" /tmp/rc-notary-app.log
xcrun stapler staple build/RetroContacts.app
rm RetroContacts-notarize.zip
# 2) DMG
STAGE=$(mktemp -d); cp -R build/RetroContacts.app "$STAGE/"; ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"; hdiutil create -volname "RetroContacts" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait | tee /tmp/rc-notary-dmg.log
grep -q "status: Accepted" /tmp/rc-notary-dmg.log
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG" 2>&1 | tail -2
spctl --assess --type execute -v build/RetroContacts.app 2>&1 | tail -2
echo "FERTIG: $PWD/$DMG"
