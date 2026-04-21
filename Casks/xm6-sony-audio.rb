cask "xm6-sony-audio" do
  version "1.0.0"
  sha256 "c204602c2d719f90ad47a758d0e90cd75b37e0a8d9f003e796b9860b3fa65e2a"

  url "https://github.com/shellingtonshreyas/xm6-macos-controller/releases/download/v#{version}/Sony.Audio.dmg"
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
