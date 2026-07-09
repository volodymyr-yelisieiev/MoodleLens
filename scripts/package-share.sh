#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null || date +%Y%m%d-%H%M)}"
PRODUCT_APP_NAME="MoodleLens"
APP_NAME="MoodleLens"
ARTIFACT_NAME="MoodleLens"
APP_VERSION="${VERSION#v}"
DEFAULT_BUILD_NUMBER=10100
if [[ "$APP_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  DEFAULT_BUILD_NUMBER=$((10#${BASH_REMATCH[1]} * 10000 + 10#${BASH_REMATCH[2]} * 100 + 10#${BASH_REMATCH[3]}))
fi
BUILD_NUMBER="${MOODLELENS_BUILD_NUMBER:-$DEFAULT_BUILD_NUMBER}"
WORK_DIR="$ROOT/build/package"
DERIVED_DATA="$WORK_DIR/DerivedData"
STAGE_DIR="$WORK_DIR/$ARTIFACT_NAME-$VERSION"
DIST_DIR="$ROOT/dist"
APP_SRC="$DERIVED_DATA/Build/Products/Release/$PRODUCT_APP_NAME.app"
APP_DST="$STAGE_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$ARTIFACT_NAME-$VERSION-macos.dmg"
DMG_TEMP_PATH="$WORK_DIR/$ARTIFACT_NAME-$VERSION-macos-rw.dmg"
DMG_MOUNT="$WORK_DIR/dmg-mount"
DMG_BACKGROUND="$ROOT/assets/dmg-background.png"
SPARKLE_ZIP_PATH="$DIST_DIR/$ARTIFACT_NAME-$VERSION-sparkle.zip"
SIGN_IDENTITY="${MOODLELENS_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${MOODLELENS_NOTARY_PROFILE:-}"
NOTARY_KEY="${MOODLELENS_NOTARY_KEY:-}"
NOTARY_KEY_ID="${MOODLELENS_NOTARY_KEY_ID:-}"
NOTARY_ISSUER="${MOODLELENS_NOTARY_ISSUER:-}"
SIGNED_RELEASE=0
NOTARIZED_RELEASE=0
DIRECT_NOTARY=0

if [ -n "$NOTARY_KEY$NOTARY_KEY_ID$NOTARY_ISSUER" ]; then
  if [ -z "$NOTARY_KEY" ] || [ -z "$NOTARY_KEY_ID" ] || [ -z "$NOTARY_ISSUER" ]; then
    echo "Direct notarization requires MOODLELENS_NOTARY_KEY, MOODLELENS_NOTARY_KEY_ID, and MOODLELENS_NOTARY_ISSUER together." >&2
    exit 1
  fi
  DIRECT_NOTARY=1
fi

if [ -n "$NOTARY_PROFILE" ] && [ "$DIRECT_NOTARY" -eq 1 ]; then
  echo "Use either MOODLELENS_NOTARY_PROFILE or direct MOODLELENS_NOTARY_KEY credentials, not both." >&2
  exit 1
fi

if [ -n "$NOTARY_PROFILE" ] || [ "$DIRECT_NOTARY" -eq 1 ]; then
  if [ -z "$SIGN_IDENTITY" ]; then
    echo "Notarized releases require MOODLELENS_SIGN_IDENTITY. Unset notarization inputs for a private local build." >&2
    exit 1
  fi
fi

if [ -n "$SIGN_IDENTITY" ]; then
  SIGNED_RELEASE=1
fi

if [ -n "$SIGN_IDENTITY" ] && { [ -n "$NOTARY_PROFILE" ] || [ "$DIRECT_NOTARY" -eq 1 ]; }; then
  NOTARIZED_RELEASE=1
fi

assess_gatekeeper() {
  local label="$1"
  shift
  printf 'Assessing %s with Gatekeeper...\n' "$label"
  spctl --assess --verbose=4 "$@"
}

rm -rf "$WORK_DIR"
mkdir -p "$STAGE_DIR" "$DIST_DIR"
cleanup() {
  if [ -d "$DMG_MOUNT" ] && /sbin/mount | grep -F " on $DMG_MOUNT " >/dev/null 2>&1; then
    hdiutil detach "$DMG_MOUNT" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
  rmdir "$ROOT/build" 2>/dev/null || true
}
trap cleanup EXIT

style_dmg() {
  osascript <<APPLESCRIPT
set dmgFolder to POSIX file "$DMG_MOUNT" as alias
set backgroundImage to POSIX file "$DMG_MOUNT/.background/dmg-background.png" as alias
tell application "Finder"
  open dmgFolder
  set current view of container window of dmgFolder to icon view
  set toolbar visible of container window of dmgFolder to false
  set statusbar visible of container window of dmgFolder to false
  set bounds of container window of dmgFolder to {100, 100, 740, 500}
  set viewOptions to the icon view options of container window of dmgFolder
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 96
  set background picture of viewOptions to backgroundImage
  set position of item "MoodleLens.app" of dmgFolder to {170, 190}
  set position of item "Applications" of dmgFolder to {470, 190}
  update dmgFolder without registering applications
  delay 1
  close container window of dmgFolder
end tell
APPLESCRIPT
}

DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}" \
xcodebuild -quiet \
  -project MoodleLens.xcodeproj \
  -scheme MoodleLens \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$APP_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build

ditto "$APP_SRC" "$APP_DST"
if [ "$SIGNED_RELEASE" -eq 1 ]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DST" >/dev/null
else
  codesign --force --deep --sign - --timestamp=none "$APP_DST" >/dev/null
fi
codesign --verify --deep --strict "$APP_DST"

ln -s /Applications "$STAGE_DIR/Applications"
mkdir -p "$STAGE_DIR/.background"
cp "$DMG_BACKGROUND" "$STAGE_DIR/.background/dmg-background.png"

rm -f "$DMG_PATH" "$DMG_TEMP_PATH" "$SPARKLE_ZIP_PATH"
ditto -c -k --norsrc --noextattr --keepParent "$APP_DST" "$SPARKLE_ZIP_PATH"
mkdir -p "$DMG_MOUNT"
hdiutil create -volname "MoodleLens $VERSION" -srcfolder "$STAGE_DIR" -format UDRW "$DMG_TEMP_PATH" >/dev/null
hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$DMG_MOUNT" "$DMG_TEMP_PATH" >/dev/null
if ! style_dmg; then
  printf 'Warning: Finder DMG styling failed; continuing with plain app-to-Applications DMG.\n' >&2
fi
sync
hdiutil detach "$DMG_MOUNT" >/dev/null
hdiutil convert "$DMG_TEMP_PATH" -format UDZO -o "$DMG_PATH" >/dev/null

if [ "$SIGNED_RELEASE" -eq 1 ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH" >/dev/null
fi

if [ "$NOTARIZED_RELEASE" -eq 1 ]; then
  if [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    NOTARY_KEY_FILE="$WORK_DIR/notary-key.p8"
    printf '%s' "$NOTARY_KEY" > "$NOTARY_KEY_FILE"
    chmod 600 "$NOTARY_KEY_FILE"
    xcrun notarytool submit "$DMG_PATH" --key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  fi
  xcrun stapler staple "$DMG_PATH"
  assess_gatekeeper "app" --type execute "$APP_DST"
  assess_gatekeeper "dmg" --type open --context context:primary-signature "$DMG_PATH"
elif [ "$SIGNED_RELEASE" -eq 1 ]; then
  printf 'Created signed build without notarization. TCC permissions should persist across updates with the same signing identity, but public Gatekeeper UX still requires notarization.\n'
else
  printf 'Created private local build: ad-hoc signed, not notarized. TCC permissions may need a fresh grant after each rebuilt app. Stable updates require MOODLELENS_SIGN_IDENTITY; public Gatekeeper UX also requires MOODLELENS_NOTARY_PROFILE.\n'
fi

printf 'Created:\n'
printf '  %s\n' "$DMG_PATH"
printf '  %s\n' "$SPARKLE_ZIP_PATH"
