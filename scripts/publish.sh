#!/bin/zsh
# Publishes the DMG that release.sh built: a GitHub Release (v<version>) holding Compositor-KR.dmg, then the Sparkle
# update feed (appcast.xml, committed to main) pointing at it, which every copy of the app checks for updates.
#
# Run release.sh first. Needs the Sparkle signing key in the login keychain (made once with Sparkle's generate_keys;
# its public half is SUPublicEDKey in Config/Info.plist), and either `gh` signed in (brew install gh; gh auth login) or
# a GitHub token allowed to write this repository's contents in GITHUB_TOKEN.
# Release notes: RELEASE_NOTES="…" ./scripts/publish.sh
#
# Versions follow upstream Compositor's number. While it stays the same, each further release of this fork adds a
# letter: 1.4.5, then 1.4.5(A), 1.4.5(B)…; when upstream moves on (1.4.6), the number follows it and the letters start
# over. The build number (CURRENT_PROJECT_VERSION) goes up by one every release, whatever the version.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/Compositor-KR.xcodeproj"
SCHEME=Compositor
APP=Proteon
# Keep the public asset name for existing update/download links.
ASSET=Compositor-KR
REPO=songhj0728/Compositor-KR
WORK="$HOME/Library/Caches/CompositorKRRelease"
SIGN_UPDATE="$WORK/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

settings=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null)
VERSION=$(print -r -- "$settings" | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')
BUILD=$(print -r -- "$settings" | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')
MINIMUM=$(print -r -- "$settings" | awk -F' = ' '/ MACOSX_DEPLOYMENT_TARGET = /{print $2; exit}')
TAG="v$VERSION"
NOTES="${RELEASE_NOTES:-$APP $VERSION}"
SOURCE="$PROJECT_DIR/dist/$APP-$VERSION.dmg"
[[ -f "$SOURCE" ]] || { echo "No $SOURCE — run scripts/release.sh first."; exit 1; }
[[ -x "$SIGN_UPDATE" ]] || { echo "Sparkle's sign_update isn't built — run scripts/release.sh first."; exit 1; }
# Sparkle offers an update by its build number, not its version: a release that doesn't raise it reaches no one.
PREVIOUS=$(sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' "$PROJECT_DIR/appcast.xml" | head -1)
if [[ -n "$PREVIOUS" ]] && (( BUILD <= PREVIOUS )); then
  echo "Build $BUILD isn't above the last release's $PREVIOUS: raise CURRENT_PROJECT_VERSION first."; exit 1
fi

# GitHub through gh when it's installed, or its REST API with GITHUB_TOKEN.
if command -v gh >/dev/null; then
  USE_GH=true
else
  USE_GH=false
  [[ -n "${GITHUB_TOKEN:-}" ]] || { echo "Install gh (brew install gh; gh auth login), or set GITHUB_TOKEN."; exit 1; }
fi
api() { curl -fsS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

if $USE_GH; then
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release $TAG already exists. Raise the version (and build number) first."; exit 1
  fi
elif api "https://api.github.com/repos/$REPO/releases/tags/$TAG" >/dev/null 2>&1; then
  echo "Release $TAG already exists. Raise the version (and build number) first."; exit 1
fi

echo "==> $APP $VERSION ($BUILD)"
# Every release names its file Compositor-KR.dmg, so …/releases/latest/download/Compositor-KR.dmg always works.
mkdir -p "$WORK/publish"
DMG="$WORK/publish/$ASSET.dmg"
cp "$SOURCE" "$DMG"

echo "==> Signing the update for Sparkle"
signature=$("$SIGN_UPDATE" "$DMG")

echo "==> Creating GitHub Release $TAG"
if $USE_GH; then
  gh release create "$TAG" "$DMG" --repo "$REPO" --title "$APP $VERSION" --notes "$NOTES"
else
  body=$(python3 -c 'import json,sys; print(json.dumps({"tag_name": sys.argv[1], "name": sys.argv[2], "body": sys.argv[3]}))' \
    "$TAG" "$APP $VERSION" "$NOTES")
  upload=$(api -X POST "https://api.github.com/repos/$REPO/releases" -d "$body" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["upload_url"].split("{")[0])')
  api -X POST -H "Content-Type: application/octet-stream" --data-binary @"$DMG" "$upload?name=$ASSET.dmg" >/dev/null
fi

echo "==> Publishing the update feed"
cat > "$PROJECT_DIR/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM</sparkle:minimumSystemVersion>
      <link>https://github.com/$REPO/releases/tag/$TAG</link>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$ASSET.dmg" $signature type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
git -C "$PROJECT_DIR" add appcast.xml
git -C "$PROJECT_DIR" commit -q -m "Publish update feed for $APP $VERSION"
git -C "$PROJECT_DIR" push -q
echo "==> Done: https://github.com/$REPO/releases/tag/$TAG"
