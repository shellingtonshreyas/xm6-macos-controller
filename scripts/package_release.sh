#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DISPLAY_NAME="Sony Audio"
APP_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.app"
DMG_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.dmg"
SHA_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.dmg.sha256"
STAGING_DIR="$ROOT_DIR/dist/release-staging"

"$ROOT_DIR/scripts/bundle_app.sh"

rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH" "$SHA_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_DISPLAY_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

shasum -a 256 "$DMG_PATH" > "$SHA_PATH"

rm -rf "$STAGING_DIR"

echo "Release DMG created at: $DMG_PATH"
echo "SHA256 file created at: $SHA_PATH"
