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

## Notes

- Pair the WH-1000XM6 in macOS Bluetooth settings before launching the app.
- Launch-at-login should be toggled after installing the final app into `/Applications`, so macOS registers the installed bundle path.
