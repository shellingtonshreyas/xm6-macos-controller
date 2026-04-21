cask "xm6-sony-audio" do
  version "0.3.1"
  sha256 "7df371e79e111447d8c00a152dad3a3731208a9409b1dec46dee48a5ca14d384"

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
