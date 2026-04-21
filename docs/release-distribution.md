# Release Distribution

Last updated: April 21, 2026

This project now supports two public distribution paths:

- GitHub Releases for direct `.zip` and `.dmg` downloads
- Homebrew Cask through this repository as a tap

## Current State

- The release bundle identifier now defaults to `io.github.shellingtonshreyas.sonyaudio`
- The packaged app version now defaults to the latest Git tag unless `SONY_APP_VERSION` is set explicitly
- The Homebrew cask lives at `Casks/xm6-sony-audio.rb`
- The current cask is configured for Apple Silicon release artifacts
- GitHub release asset filenames are normalized to dotted names such as `Sony.Audio.dmg`

## Why Notarization Still Matters

Homebrew installs casks with quarantine by default.

That means a Homebrew cask becomes much more trustworthy once the downloaded release is:

- signed with a `Developer ID Application` certificate
- notarized with Apple's notary service
- stapled before distribution

The repo already supports this in `scripts/package_release.sh` when `SONY_NOTARY_PROFILE` is configured.

## Release Checklist

1. Run tests.
2. Build the release DMG.
3. Regenerate the Homebrew cask from the new DMG checksum.
4. Validate the cask locally with Homebrew.
5. Tag and publish the GitHub Release.

Example:

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift test
SONY_APP_VERSION=0.3.1 ./scripts/package_release.sh
./scripts/generate_homebrew_cask.sh 0.3.1
brew style Casks/xm6-sony-audio.rb
```

For a public notarized build:

```bash
SONY_APP_VERSION=0.3.1 \
SONY_NOTARY_PROFILE="sony-notary" \
./scripts/package_release.sh
```

## Homebrew Install Commands

```bash
brew tap shellingtonshreyas/xm6-macos-controller https://github.com/shellingtonshreyas/xm6-macos-controller
brew install --cask shellingtonshreyas/xm6-macos-controller/xm6-sony-audio
```

Use the explicit tap URL because the source repository is not named with Homebrew's default `homebrew-...` tap convention.
