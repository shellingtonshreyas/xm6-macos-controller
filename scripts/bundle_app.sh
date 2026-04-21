#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT_NAME="SonyMacApp"
APP_DISPLAY_NAME="Sony Audio"
DEFAULT_BUNDLE_ID="io.github.shellingtonshreyas.sonyaudio"
DEFAULT_APP_VERSION="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
DEFAULT_BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || printf '1')"
BUNDLE_ID="${SONY_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
APP_VERSION="${SONY_APP_VERSION:-${DEFAULT_APP_VERSION:-0.1.0}}"
BUILD_NUMBER="${SONY_BUILD_NUMBER:-$DEFAULT_BUILD_NUMBER}"
EXPLICIT_CODESIGN_IDENTITY="${SONY_CODESIGN_IDENTITY:-}"
REQUIRE_DEVELOPER_ID="${SONY_REQUIRE_DEVELOPER_ID:-0}"
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build -c release --package-path "$ROOT_DIR" >/dev/null
BUILD_DIR="$(env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build -c release --package-path "$ROOT_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$PRODUCT_NAME"
APP_DIR="$ROOT_DIR/dist/$APP_DISPLAY_NAME.app"
ZIP_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.zip"
LEGACY_APP_DIR="$ROOT_DIR/dist/$PRODUCT_NAME.app"
TEMP_RELEASE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sony-audio-release.XXXXXX")"
TEMP_APP_DIR="$TEMP_RELEASE_ROOT/$APP_DISPLAY_NAME.app"
CONTENTS_DIR="$TEMP_APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$ROOT_DIR/dist/AppIcon.iconset"
MASTER_ICON="$ROOT_DIR/dist/AppIcon-1024.png"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"

cleanup() {
    rm -rf "$TEMP_RELEASE_ROOT"
}

trap cleanup EXIT

detect_developer_id_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
        | head -n 1
}

sign_app_bundle() {
    local identity="$1"

    xattr -cr "$TEMP_APP_DIR" 2>/dev/null || true

    if [[ "$identity" == "-" ]]; then
        codesign --force --deep --sign - "$TEMP_APP_DIR" >/dev/null
        codesign --verify --deep --strict --verbose=2 "$TEMP_APP_DIR" >/dev/null
        echo "Signed app with ad hoc identity."
        return
    fi

    local -a sign_args
    sign_args=(
        --force
        --deep
        --sign "$identity"
        --timestamp
    )

    if [[ "$identity" == Developer\ ID\ Application:* ]]; then
        sign_args+=(--options runtime)
    fi

    codesign "${sign_args[@]}" "$TEMP_APP_DIR" >/dev/null
    codesign --verify --deep --strict --verbose=2 "$TEMP_APP_DIR" >/dev/null
    echo "Signed app with: $identity"
}

rm -rf "$APP_DIR"
rm -rf "$LEGACY_APP_DIR"
rm -rf "$ICONSET_DIR"
rm -rf "$TEMP_APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_BINARY" "$MACOS_DIR/$PRODUCT_NAME"
chmod +x "$MACOS_DIR/$PRODUCT_NAME"

swift "$ROOT_DIR/scripts/generate_app_icon.swift" "$MASTER_ICON"
mkdir -p "$ICONSET_DIR"
cp "$MASTER_ICON" "$ICONSET_DIR/icon_512x512@2x.png"
sips -z 16 16 "$MASTER_ICON" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$MASTER_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$MASTER_ICON" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$MASTER_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$MASTER_ICON" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$MASTER_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER_ICON" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$MASTER_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER_ICON" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

find "$BUILD_DIR" -maxdepth 2 -type d -name '*.bundle' -print0 2>/dev/null | while IFS= read -r -d '' bundle; do
    cp -R "$bundle" "$RESOURCES_DIR/"
done

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$PRODUCT_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Control Sony WH-1000XM6 headphones from the menu bar.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
    CODESIGN_IDENTITY="$EXPLICIT_CODESIGN_IDENTITY"

    if [[ -z "$CODESIGN_IDENTITY" ]]; then
        CODESIGN_IDENTITY="$(detect_developer_id_identity)"
    fi

    if [[ -n "$CODESIGN_IDENTITY" ]]; then
        sign_app_bundle "$CODESIGN_IDENTITY"
    elif [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
        echo "A Developer ID Application certificate is required for this build." >&2
        echo "Install one in Keychain Access or Xcode, then re-run the release build." >&2
        exit 1
    else
        sign_app_bundle "-"
    fi
fi

rm -f "$ZIP_PATH"
if command -v ditto >/dev/null 2>&1; then
    ditto -c -k --sequesterRsrc --keepParent "$TEMP_APP_DIR" "$ZIP_PATH"
fi

# Keep a local .app in dist for convenience, but the clean release artifacts
# come from the zip/DMG because sync-enabled folders like Documents can reattach
# Finder/File Provider metadata to copied app bundles.
ditto "$TEMP_APP_DIR" "$APP_DIR"

rm -rf "$ICONSET_DIR"

echo "Bundled app created at: $APP_DIR"
echo "Zip archive created at: $ZIP_PATH"
