# Contributing

Thanks for helping improve Sony Audio.

## Before Opening a Bug Report

Please include as much of the following as you can:

- macOS version
- whether the app was run from source or from a bundled `.app`
- whether the XM6 was also connected to a phone or tablet
- exact steps to reproduce the problem
- the exact error text shown in the app
- transport logs captured from Terminal when the issue is connection-related

For connection and protocol issues, please run the app from Terminal:

```bash
cd '/path/to/xm6-macos-controller'
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift run SonyMacApp 2>&1 | tee /tmp/sony-xm6-connect.log
```

Then attach or paste the lines that start with `[SonyRFCOMMTransport]`.

## Development Checklist

Before opening a pull request:

1. Run the test suite.

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift test
```

2. If you touched packaging or the app bundle layout, also run:

```bash
./scripts/bundle_app.sh
```

3. Keep changes focused. Small PRs are easier to review and safer to verify on hardware.

## Pull Request Notes

Helpful PR descriptions usually include:

- what changed
- why it changed
- how it was tested
- whether real XM6 hardware was used
- any logs, packet captures, or screenshots that explain the behavior

## Scope

Especially useful contributions:

- connection reliability improvements
- transport logging and diagnostics
- UI polish that matches the existing design language
- tests for protocol/session behavior
- packaging and release automation improvements

Please avoid committing generated `dist/` artifacts or local machine metadata.
