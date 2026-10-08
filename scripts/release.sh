#!/bin/zsh
# Builds the Proteon DMG into dist/.
#
# With a "Developer ID Application" certificate in the login keychain and notarization credentials saved once with
#     xcrun notarytool store-credentials "compositor-kr-notary" --apple-id "…" --team-id 78U738RSNN
# the app and DMG are signed and notarized, and open without warnings on any Mac. Without them (no paid Apple
# Developer Program membership), the app is signed for running locally and not notarized: on another Mac it opens the
# first time with right-click ▸ Open.
#
# The DMG window uses create-dmg (brew install create-dmg) when it's installed, and plain hdiutil otherwise. Its
# background is scripts/dmg/dmg-bg.jpg (600 × 380, the window's exact size) plus dmg-bg-retina.jpg (1200 × 760).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/Compositor-KR.xcodeproj"
SCHEME=Compositor
APP=Proteon
BUILT_APP=Compositor-KR
TEAM=78U738RSNN
IDENTITY="Developer ID Application"
NOTARY_PROFILE=compositor-kr-notary
# Built outside cloud-synced folders: the extended attributes they add to files make code signing fail.
WORK="$HOME/Library/Caches/CompositorKRRelease"
DIST="$PROJECT_DIR/dist"

settings=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null)
VERSION=$(print -r -- "$settings" | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')
BUILD=$(print -r -- "$settings" | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')
echo "==> $APP $VERSION ($BUILD)"

# Developer ID and notarization when both are set up; a local signature otherwise.
DEVELOPER_ID=false
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then DEVELOPER_ID=true; fi
NOTARIZE=false
if $DEVELOPER_ID && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then NOTARIZE=true; fi
if ! $DEVELOPER_ID; then
  echo "    No “$IDENTITY” certificate: signing for local use, without notarization."
elif ! $NOTARIZE; then
  echo "    No notarization profile “$NOTARY_PROFILE”: signing with Developer ID, without notarization."
fi

rm -rf "$WORK"
mkdir -p "$WORK" "$DIST"

echo "==> Archiving a Release build"
if $DEVELOPER_ID; then
  signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM")
else
  # No hardened runtime with an ad hoc signature: its library validation only loads frameworks signed by the app's own
  # team, and ad hoc code has none, so the app would die at launch failing to load Sparkle. Notarization is what needs
  # the hardened runtime, and an ad hoc build isn't notarized.
  signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="" ENABLE_HARDENED_RUNTIME=NO)
fi
xcodebuild archive -quiet \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$WORK/$APP.xcarchive" -derivedDataPath "$WORK/DerivedData" \
  "${signing[@]}"

if $DEVELOPER_ID; then
  echo "==> Exporting, signed with Developer ID"
  xcodebuild -exportArchive -quiet \
    -archivePath "$WORK/$APP.xcarchive" \
    -exportOptionsPlist "$PROJECT_DIR/scripts/ExportOptions.plist" \
    -exportPath "$WORK/export"
  mv "$WORK/export/$BUILT_APP.app" "$WORK/export/$APP.app"
  APP_PATH="$WORK/export/$APP.app"
else
  mkdir -p "$WORK/export"
  ditto "$WORK/$APP.xcarchive/Products/Applications/$BUILT_APP.app" "$WORK/export/$APP.app"
  APP_PATH="$WORK/export/$APP.app"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# A signature can verify and the app still be refused at launch (a framework the loader won't map), so start it and
# make sure it's still running a few seconds later.
echo "==> Checking that the app launches"
"$APP_PATH/Contents/MacOS/$BUILT_APP" >"$WORK/launch.log" 2>&1 &
LAUNCHED=$!
sleep 5
if ! kill -0 $LAUNCHED 2>/dev/null; then
  echo "The built app quit at launch:"; head -5 "$WORK/launch.log"; exit 1
fi
kill $LAUNCHED; wait $LAUNCHED 2>/dev/null || true

if $NOTARIZE; then
  echo "==> Notarizing the app"
  ditto -c -k --keepParent "$APP_PATH" "$WORK/$APP.zip"
  xcrun notarytool submit "$WORK/$APP.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
fi

echo "==> Building the DMG"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
DMG="$DIST/$APP-$VERSION.dmg"
rm -f "$DMG"
if command -v create-dmg >/dev/null; then
  # Icon centers in the DMG window, in points from its top-left.
  APP_X=160
  APPLICATIONS_X=440
  ICON_Y=180
  background=()
  LOW="$PROJECT_DIR/scripts/dmg/dmg-bg.jpg"
  HIGH="$PROJECT_DIR/scripts/dmg/dmg-bg-retina.jpg"
  if [[ -f "$LOW" && -f "$HIGH" ]]; then
    # Finder takes one background file; a TIFF holding both sizes stays sharp on Retina displays.
    sips -s format png -s dpiWidth 72 -s dpiHeight 72 "$LOW" --out "$WORK/background.png" >/dev/null
    sips -s format png -s dpiWidth 144 -s dpiHeight 144 "$HIGH" --out "$WORK/background@2x.png" >/dev/null
    tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null
    background=(--background "$WORK/background.tiff")
  elif [[ -f "$LOW" ]]; then
    background=(--background "$LOW")
  fi
  create-dmg \
    --volname "$APP" \
    --window-pos 200 120 --window-size 600 380 \
    --icon-size 128 --text-size 13 \
    --icon "$APP.app" "$APP_X" "$ICON_Y" --hide-extension "$APP.app" \
    --app-drop-link "$APPLICATIONS_X" "$ICON_Y" \
    "${background[@]}" \
    "$DMG" "$STAGE"
else
  # The app and a link to Applications to drag it onto, without create-dmg's window layout.
  ln -s /Applications "$STAGE/Applications"
  # `hdiutil create -srcfolder` lays out the filesystem by mounting a scratch image partway through,
  # which some sandboxed environments refuse ("Operation not permitted") even though they allow every
  # other disk-image operation. makehybrid builds the HFS+ image straight from the folder without
  # mounting anything, and convert then compresses it the same way `-format UDZO` would have.
  HYBRID="$WORK/hybrid.dmg"
  hdiutil makehybrid -quiet -hfs -hfs-volume-name "$APP" -o "$HYBRID" "$STAGE"
  hdiutil convert -quiet "$HYBRID" -format UDZO -o "$DMG"
  rm -f "$HYBRID"
fi

if $DEVELOPER_ID; then
  echo "==> Signing the DMG"
  codesign --sign "$IDENTITY" --timestamp "$DMG"
fi
if $NOTARIZE; then
  echo "==> Notarizing the DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "==> What Gatekeeper will say on another Mac"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  spctl --assess --type execute --verbose=2 "$APP_PATH"
fi
echo "==> Done: $DMG"
