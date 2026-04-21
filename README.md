# Sony Audio

[![CI](https://github.com/shellingtonshreyas/xm6-macos-controller/actions/workflows/ci.yml/badge.svg)](https://github.com/shellingtonshreyas/xm6-macos-controller/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black.svg)](Package.swift)

Native macOS controller for the Sony WH-1000XM6, built in SwiftUI with a resident menu bar mode and a direct RFCOMM transport.

## Highlights

- Native SwiftUI app with a menu bar quick-control surface
- Direct macOS RFCOMM transport for XM6 control commands
- Automated Swift test coverage for connection and control-session behavior
- Public CI workflow on every push and pull request
- Local release tooling for `.app`, `.zip`, and `.dmg` packaging
- Structured issue templates, contributing guide, and security policy

## Feature Status

| Feature | Status | Notes |
| --- | --- | --- |
| XM6 control-channel connection | In active validation | Connection recovery and transport logging are built in. |
| Noise Cancelling / Ambient / Off | Supported | Uses XM6 RFCOMM control packets. |
| Ambient Sound level 1-20 | Supported | Includes the maximum ambient level. |
| Focus on Voice | Supported | Available in Ambient mode. |
| Volume 0-30 | Supported | Routed through the native XM6 playback parameter channel. |
| Battery level and charging state | Supported when reported by the headset | Startup sync is best-effort and can populate asynchronously. |
| DSEE Extreme | Supported | Uses the verified XM6 command channel. |
| Speak-to-Chat | Supported | Uses the verified XM6 command channel. |
| Menu bar quick controls | Supported | Connect, noise control, volume, and quick toggles. |
| Custom EQ bands | Not exposed | Captured protocol work is incomplete for full manual EQ editing. |
| Virtual surround / sound position | Not exposed | Not mapped in the current driver. |

## Current Limitations

- XM6 control-channel startup is still being validated against real hardware across different macOS versions.
- The app depends on the headset already being paired and connected to the Mac as an audio device.
- Full manual EQ editing is not shipped yet because the XM6 EQ write path is not fully mapped.
- Some state refreshes arrive asynchronously from the headset rather than as immediate request-response pairs.

## Quick Start

1. Pair the `WH-1000XM6` in macOS Bluetooth settings first.
2. If multipoint is enabled, disconnect the headset from your phone or tablet during first setup.
3. Build or download the app.
4. Connect the XM6 from the device list in the app or the menu bar.

## Build From Source

Development build:

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build
```

Run the app directly:

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift run SonyMacApp
```

Run tests:

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift test
```

## Create a Local `.app`

```bash
./scripts/bundle_app.sh
```

This creates:

- `dist/Sony Audio.app`
- `dist/Sony Audio.zip`

Install into `/Applications`:

```bash
./scripts/install_app.sh
```

Or drag `dist/Sony Audio.app` into `/Applications`.

## Create a Release Installer

```bash
./scripts/package_release.sh
```

This creates:

- `dist/Sony Audio.dmg`
- `dist/Sony Audio.dmg.sha256`

### Public notarized release

One-time setup:

1. Install a `Developer ID Application` certificate in your login keychain.
2. Store notarization credentials with `notarytool`.

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

- The scripts automatically use the first available `Developer ID Application` identity unless `SONY_CODESIGN_IDENTITY` is set.
- When `SONY_NOTARY_PROFILE` is set, the app zip is notarized and stapled first, then the final DMG is notarized and stapled.
- `SONY_REQUIRE_DEVELOPER_ID=1` forces the build to fail if no public distribution certificate is available.

## Troubleshooting

If the headset connects for audio but the control surface does not populate:

1. Make sure the XM6 is already connected to this Mac in Bluetooth settings.
2. Temporarily disconnect the headset from any nearby phone or tablet.
3. Relaunch the app from Terminal so transport logs are captured:

```bash
cd '/path/to/xm6-macos-controller'
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift run SonyMacApp 2>&1 | tee /tmp/sony-xm6-connect.log
```

4. Open an issue and include the lines that start with `[SonyRFCOMMTransport]`.

## Support

- Use the bug report template for connection, control, or packaging issues.
- Include the app version or commit SHA, your macOS version, and whether the headset was also connected to another device.
- For security issues, follow the private reporting guidance in [.github/SECURITY.md](.github/SECURITY.md) instead of opening a public issue.

## Project Structure

- `Sources/SonyMacApp` — app source
- `Tests/SonyMacAppTests` — unit and session tests
- `scripts/bundle_app.sh` — builds a release `.app` bundle
- `scripts/install_app.sh` — installs the bundled app into `/Applications`
- `scripts/package_release.sh` — builds the DMG and handles notarization when configured

## Contributing

Bug reports and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR or filing a protocol/connection issue.

## Community

- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Support](SUPPORT.md)
- [Security Policy](.github/SECURITY.md)

## Security

Please read [.github/SECURITY.md](.github/SECURITY.md) before reporting a vulnerability.

## License

This project is licensed under the GNU GPL v3. See [LICENSE](LICENSE).
