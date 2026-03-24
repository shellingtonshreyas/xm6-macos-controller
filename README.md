# Sony Audio

Native macOS controller for the Sony WH-1000XM6, built in SwiftUI with a resident menu bar mode and a direct macOS RFCOMM transport.

## What it does

- Connects to paired `WH-1000XM6` headphones over Sony's verified XM6 RFCOMM control channel
- Syncs and controls:
  - battery state
  - Noise Cancelling / Ambient Sound / Off
  - Ambient level
  - Focus on Voice
  - DSEE Extreme
  - Speak-to-Chat
- Includes a menu bar resident mode with quick controls
- Supports launch-at-login from the bundled app
- Uses a native startup splash and a graphite/champagne macOS interface

## What it does not do

- Custom EQ bands are not exposed
- Virtual surround / positional audio controls are not exposed
- BLE diagnostics are no longer part of the main shipped experience

## Build a final `.app`

```bash
./scripts/bundle_app.sh
```

This creates:

- `dist/Sony Audio.app`
- `dist/Sony Audio.zip`

## Create a GitHub Releases installer

```bash
./scripts/package_release.sh
```

This creates:

- `dist/Sony Audio.dmg`
- `dist/Sony Audio.dmg.sha256`

## Create a public notarized release

One-time setup:

1. Install a `Developer ID Application` certificate in your login keychain.
2. Store notarization credentials in Keychain with `notarytool`.

Apple ID example:

```bash
xcrun notarytool store-credentials "sony-notary" --apple-id "you@example.com" --team-id "TEAMID"
```

App Store Connect API key example:

```bash
xcrun notarytool store-credentials "sony-notary" --key "/path/to/AuthKey_ABC1234567.p8" --key-id "ABC1234567" --issuer "00000000-0000-0000-0000-000000000000"
```

Public release build:

```bash
SONY_BUNDLE_ID="com.example.sonyaudio" \
SONY_APP_VERSION="1.0.0" \
SONY_BUILD_NUMBER="1" \
SONY_NOTARY_PROFILE="sony-notary" \
./scripts/package_release.sh
```

Notes:

- The scripts automatically use the first available `Developer ID Application` identity unless you set `SONY_CODESIGN_IDENTITY`.
- When `SONY_NOTARY_PROFILE` is set, the app zip is notarized and stapled first, then the final DMG is notarized and stapled.
- `SONY_REQUIRE_DEVELOPER_ID=1` forces the build to fail if no public distribution certificate is available.

## Install into `/Applications`

```bash
./scripts/install_app.sh
```

Or drag `dist/Sony Audio.app` into `/Applications`.

## Development build

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build
```

## Project structure

- `Sources/SonyMacApp` — app source
- `scripts/bundle_app.sh` — builds a release `.app` bundle
- `scripts/install_app.sh` — installs the bundled app into `/Applications`
- `scripts/package_release.sh` — builds the drag-to-Applications DMG and handles notarization when configured

## Notes

- Pair the WH-1000XM6 in macOS Bluetooth settings before launching the app.
- Launch-at-login should be toggled after installing the final app into `/Applications`, so macOS registers the installed bundle path.
