#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:?Usage: scripts/generate-appcast.sh <version>}"
ZIP_PATH="$ROOT/dist/MoodleLens-$VERSION-sparkle.zip"
APPCAST_DIR="$ROOT/dist/appcast"
APPCAST_PATH="$ROOT/dist/appcast.xml"
DOWNLOAD_URL_PREFIX="${MOODLELENS_DOWNLOAD_URL_PREFIX:-https://github.com/volodymyr-yelisieiev/MoodleLens/releases/download/$VERSION/}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-moodlelens-volodymyr-yelisieiev}"

if [ ! -f "$ZIP_PATH" ]; then
  echo "Missing Sparkle ZIP: $ZIP_PATH" >&2
  echo "Run scripts/package-share.sh $VERSION first." >&2
  exit 1
fi

if [ -n "${SPARKLE_TOOLS_DIR:-}" ] && [ -x "$SPARKLE_TOOLS_DIR/generate_appcast" ]; then
  GENERATE_APPCAST="$SPARKLE_TOOLS_DIR/generate_appcast"
else
  GENERATE_APPCAST="$(
    find "$HOME/Library/Developer/Xcode/DerivedData" \
      -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
      -type f \
      -print \
      -quit
  )"
fi

if [ -z "$GENERATE_APPCAST" ] || [ ! -x "$GENERATE_APPCAST" ]; then
  echo "Could not find Sparkle generate_appcast. Resolve Swift packages or set SPARKLE_TOOLS_DIR." >&2
  exit 1
fi

rm -rf "$APPCAST_DIR"
mkdir -p "$APPCAST_DIR"
cp "$ZIP_PATH" "$APPCAST_DIR/"

cat > "$APPCAST_DIR/MoodleLens-$VERSION-sparkle.md" <<NOTES
# MoodleLens $VERSION

- Ask uses the standard capture-excluded screenshot path with compact Moodle Browser Context when available.
- The response bubble shows scrollable Ask history with native Markdown rendering.
- Default Instructions are Moodle assessment focused and evidence-bound.
- Grant / Repair now triggers only the native macOS permission prompt instead of also opening System Settings.
- DMG is signed/notarized when release credentials are provided; otherwise it remains ad-hoc.
NOTES

if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    --embed-release-notes \
    "$APPCAST_DIR"
else
  "$GENERATE_APPCAST" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    --embed-release-notes \
    "$APPCAST_DIR"
fi

cp "$APPCAST_DIR/appcast.xml" "$APPCAST_PATH"
echo "Updated $APPCAST_PATH"
