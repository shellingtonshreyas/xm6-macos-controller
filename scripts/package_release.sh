#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DISPLAY_NAME="Sony Audio"
APP_NAME="$APP_DISPLAY_NAME.app"
APP_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.app"
DMG_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.dmg"
SHA_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.dmg.sha256"
STAGING_DIR="$ROOT_DIR/dist/release-staging"
BACKGROUND_DIR="$STAGING_DIR/.background"
BACKGROUND_PATH="$BACKGROUND_DIR/installer-background.png"
RW_DMG_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME-rw.dmg"
MOUNT_POINT="$ROOT_DIR/dist/release-mount"

cleanup() {
  set +e
  if mount | grep -Fq "on $MOUNT_POINT "; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  rm -rf "$STAGING_DIR" "$MOUNT_POINT"
  rm -f "$RW_DMG_PATH"
}

trap cleanup EXIT

"$ROOT_DIR/scripts/bundle_app.sh"

rm -rf "$STAGING_DIR"
rm -rf "$MOUNT_POINT"
rm -f "$DMG_PATH" "$SHA_PATH" "$RW_DMG_PATH"
mkdir -p "$BACKGROUND_DIR" "$MOUNT_POINT"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
swift "$ROOT_DIR/scripts/generate_dmg_background.swift" "$BACKGROUND_PATH"

STAGING_SIZE_KB=$(du -sk "$STAGING_DIR" | awk '{print $1}')
DMG_SIZE_MB=$((STAGING_SIZE_KB / 1024 + 80))

hdiutil create \
  -ov \
  -size "${DMG_SIZE_MB}m" \
  -fs HFS+ \
  -volname "$APP_DISPLAY_NAME" \
  "$RW_DMG_PATH" >/dev/null

hdiutil attach \
  -quiet \
  -nobrowse \
  -mountpoint "$MOUNT_POINT" \
  "$RW_DMG_PATH" >/dev/null

ditto "$APP_PATH" "$MOUNT_POINT/$APP_NAME"
ln -s /Applications "$MOUNT_POINT/Applications"
mkdir -p "$MOUNT_POINT/.background"
cp "$BACKGROUND_PATH" "$MOUNT_POINT/.background/installer-background.png"
chflags hidden "$MOUNT_POINT/.background" || true

if command -v SetFile >/dev/null 2>&1; then
  SetFile -a V "$MOUNT_POINT/.background" || true
fi

if ! osascript <<EOF
tell application "Finder"
  tell disk "$APP_DISPLAY_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 1000, 680}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set text size of theViewOptions to 14
    set background picture of theViewOptions to (POSIX file "$MOUNT_POINT/.background/installer-background.png" as alias)
    set position of item "$APP_NAME" of container window to {214, 264}
    set position of item "Applications" of container window to {664, 264}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF
then
  echo "Warning: could not apply custom Finder layout; continuing with a standard DMG window." >&2
fi

bless --folder "$MOUNT_POINT" --openfolder "$MOUNT_POINT" >/dev/null 2>&1 || true
sync
hdiutil detach "$MOUNT_POINT" -quiet >/dev/null

hdiutil convert \
  "$RW_DMG_PATH" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null

shasum -a 256 "$DMG_PATH" > "$SHA_PATH"

echo "Release DMG created at: $DMG_PATH"
echo "SHA256 file created at: $SHA_PATH"
