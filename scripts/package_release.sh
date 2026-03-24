#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DISPLAY_NAME="Sony Audio"
APP_NAME="$APP_DISPLAY_NAME.app"
APP_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.app"
ZIP_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.zip"
DMG_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.dmg"
SHA_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.dmg.sha256"
STAGING_DIR="$ROOT_DIR/dist/release-staging"
BACKGROUND_DIR="$STAGING_DIR/.background"
BACKGROUND_PATH="$BACKGROUND_DIR/installer-background.png"
RW_DMG_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME-rw.dmg"
MOUNT_POINT="/Volumes/$APP_DISPLAY_NAME"
NOTARY_PROFILE="${SONY_NOTARY_PROFILE:-}"
NOTARY_DIR="$ROOT_DIR/dist/notary"
REQUIRE_DEVELOPER_ID="${SONY_REQUIRE_DEVELOPER_ID:-0}"

cleanup() {
  set +e
  if mount | grep -Fq "on $MOUNT_POINT "; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  rm -rf "$STAGING_DIR"
  rm -f "$RW_DMG_PATH"
}

trap cleanup EXIT

extract_json_field() {
  local key="$1"
  local json_path="$2"

  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$json_path" | head -n 1
}

app_is_signed_with_developer_id() {
  codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -Fq "Authority=Developer ID Application:"
}

notarize_artifact() {
  local path="$1"
  local label="$2"
  local stem="$3"
  local result_path="$NOTARY_DIR/$stem-submit.json"
  local log_path="$NOTARY_DIR/$stem-log.json"
  local submission_id=""

  rm -f "$result_path" "$log_path"
  echo "Submitting $label for notarization..."

  if ! xcrun notarytool submit "$path" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$result_path"; then
    if [[ -f "$result_path" ]]; then
      submission_id="$(extract_json_field id "$result_path")"
    fi

    if [[ -n "$submission_id" ]]; then
      xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" "$log_path" >/dev/null 2>&1 || true
      echo "Notarization log saved to: $log_path" >&2
    fi

    echo "Notarization failed for $label." >&2
    cat "$result_path" >&2 || true
    return 1
  fi

  if [[ -f "$result_path" ]]; then
    submission_id="$(extract_json_field id "$result_path")"
  fi
  echo "Notarization accepted for $label${submission_id:+ (submission id: $submission_id)}."
}

apply_finder_layout() {
  osascript - "$APP_DISPLAY_NAME" "$APP_NAME" <<'APPLESCRIPT'
on run argv
  set volumeName to item 1 of argv
  set appName to item 2 of argv

  tell application "Finder"
    repeat 40 times
      if exists disk volumeName then exit repeat
      delay 0.25
    end repeat

    if not (exists disk volumeName) then error "Disk did not appear in Finder."

    tell disk volumeName
      open

      repeat 20 times
        if exists container window then exit repeat
        delay 0.25
      end repeat

      if not (exists container window) then error "Finder window did not open."

      set dmgWindow to container window
      set current view of dmgWindow to icon view
      set toolbar visible of dmgWindow to false
      set statusbar visible of dmgWindow to false
      set bounds of dmgWindow to {120, 120, 1000, 680}

      set theViewOptions to the icon view options of dmgWindow
      set arrangement of theViewOptions to not arranged
      set icon size of theViewOptions to 128
      set text size of theViewOptions to 14
      set background picture of theViewOptions to file ".background:installer-background.png"

      set position of item appName of dmgWindow to {214, 264}
      set position of item "Applications" of dmgWindow to {664, 264}

      update without registering applications
      delay 1
      close
      open
    end tell
  end tell
end run
APPLESCRIPT
}

if [[ -n "$NOTARY_PROFILE" ]]; then
  REQUIRE_DEVELOPER_ID=1
fi

export SONY_REQUIRE_DEVELOPER_ID="$REQUIRE_DEVELOPER_ID"
"$ROOT_DIR/scripts/bundle_app.sh"

if [[ -n "$NOTARY_PROFILE" ]]; then
  mkdir -p "$NOTARY_DIR"

  if ! app_is_signed_with_developer_id; then
    echo "A public notarized release requires a Developer ID Application signature." >&2
    echo "Install a Developer ID Application certificate, or set SONY_CODESIGN_IDENTITY to one in your keychain." >&2
    exit 1
  fi

  notarize_artifact "$ZIP_PATH" "$APP_NAME zip" "app"
  xcrun stapler staple -q "$APP_PATH"
  xcrun stapler validate -q "$APP_PATH"
  echo "Stapled notarization ticket to the app bundle."
elif ! app_is_signed_with_developer_id; then
  echo "Warning: building an unsigned public installer fallback." >&2
  echo "Add a Developer ID Application certificate and SONY_NOTARY_PROFILE for a Gatekeeper-friendly release." >&2
else
  echo "Warning: app is signed with Developer ID, but SONY_NOTARY_PROFILE is not set." >&2
  echo "Warning: Gatekeeper may still warn because this release is not notarized." >&2
fi

rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH" "$SHA_PATH" "$RW_DMG_PATH"
mkdir -p "$BACKGROUND_DIR"

if [[ -d "$MOUNT_POINT" ]] && ! mount | grep -Fq "on $MOUNT_POINT "; then
  rmdir "$MOUNT_POINT" 2>/dev/null || true
fi

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

if ! apply_finder_layout; then
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

if [[ -n "$NOTARY_PROFILE" ]]; then
  hdiutil verify "$DMG_PATH" >/dev/null
  notarize_artifact "$DMG_PATH" "$APP_DISPLAY_NAME DMG" "dmg"
  xcrun stapler staple -q "$DMG_PATH"
  xcrun stapler validate -q "$DMG_PATH"
  echo "Stapled notarization ticket to the DMG."
fi

shasum -a 256 "$DMG_PATH" > "$SHA_PATH"

echo "Release DMG created at: $DMG_PATH"
echo "SHA256 file created at: $SHA_PATH"
