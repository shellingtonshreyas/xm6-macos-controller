#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CASK_DIR="$ROOT_DIR/Casks"
CASK_PATH="$CASK_DIR/xm6-sony-audio.rb"
VERSION_INPUT="${1:-${SONY_APP_VERSION:-}}"
VERSION="${VERSION_INPUT#v}"
DMG_SHA_PATH="$ROOT_DIR/dist/Sony Audio.dmg.sha256"

if [[ -z "$VERSION" ]]; then
  VERSION="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi

if [[ -z "$VERSION" ]]; then
  echo "Could not determine a release version. Pass one explicitly, for example: ./scripts/generate_homebrew_cask.sh 0.3.1" >&2
  exit 1
fi

if [[ ! -f "$DMG_SHA_PATH" ]]; then
  echo "Missing DMG checksum file at $DMG_SHA_PATH. Run ./scripts/package_release.sh first." >&2
  exit 1
fi

SHA256="$(awk '{print $1}' "$DMG_SHA_PATH")"

mkdir -p "$CASK_DIR"

cat > "$CASK_PATH" <<EOF
cask "xm6-sony-audio" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/shellingtonshreyas/xm6-macos-controller/releases/download/v#{version}/Sony%20Audio.dmg"
  name "Sony Audio"
  desc "Controller for Sony WH-1000XM6 headphones"
  homepage "https://github.com/shellingtonshreyas/xm6-macos-controller"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Sony Audio.app"

  zap trash: [
    "~/Library/Preferences/io.github.shellingtonshreyas.sonyaudio.plist",
    "~/Library/Saved Application State/io.github.shellingtonshreyas.sonyaudio.savedState",
  ]

  caveats <<~EOS
    This cask currently installs the Apple Silicon release build.
    Public notarization is still optional in the current release tooling, so Gatekeeper may
    ask for manual approval on systems where the release artifact is not notarized.
  EOS
end
EOF

echo "Updated Homebrew cask at: $CASK_PATH"
