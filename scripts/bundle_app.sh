#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT_NAME="SonyMacApp"
APP_DISPLAY_NAME="Sony Audio"
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build -c release --package-path "$ROOT_DIR" >/dev/null
BUILD_DIR="$(env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build -c release --package-path "$ROOT_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$PRODUCT_NAME"
APP_DIR="$ROOT_DIR/dist/$APP_DISPLAY_NAME.app"
ZIP_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.zip"
LEGACY_APP_DIR="$ROOT_DIR/dist/$PRODUCT_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$ROOT_DIR/dist/AppIcon.iconset"
MASTER_ICON="$ROOT_DIR/dist/AppIcon-1024.png"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"
ICON_SOURCE="$ROOT_DIR/assets/app-icon-source.webp"

rm -rf "$APP_DIR"
rm -rf "$LEGACY_APP_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_BINARY" "$MACOS_DIR/$PRODUCT_NAME"
chmod +x "$MACOS_DIR/$PRODUCT_NAME"

if [[ -f "$ICON_SOURCE" ]]; then
    swift "$ROOT_DIR/scripts/generate_app_icon.swift" "$MASTER_ICON" "$ICON_SOURCE"
else
    swift "$ROOT_DIR/scripts/generate_app_icon.swift" "$MASTER_ICON"
fi
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
    <string>local.sonyaudio</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

rm -f "$ZIP_PATH"
if command -v ditto >/dev/null 2>&1; then
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
fi

rm -rf "$ICONSET_DIR"

echo "Bundled app created at: $APP_DIR"
echo "Zip archive created at: $ZIP_PATH"
