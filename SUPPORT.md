# Support

## Before Opening an Issue

Please check the following first:

- the XM6 is paired in macOS Bluetooth settings
- the XM6 is already connected to the Mac as an audio device
- the headset is not actively connected to another phone or tablet if multipoint is causing conflicts
- you are using the latest `main` branch or the latest public release

## Connection Diagnostics

For connection issues, run the app from Terminal so the transport logs are captured:

```bash
cd '/path/to/xm6-macos-controller'
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift run SonyMacApp 2>&1 | tee /tmp/sony-xm6-connect.log
```

When you open an issue, include:

- the exact error text shown in the app
- the macOS version
- whether you ran from source, a zip, or a DMG install
- the lines that start with `[SonyRFCOMMTransport]`

## Security

Do not report security vulnerabilities in a public issue. Please follow the guidance in [.github/SECURITY.md](.github/SECURITY.md).
