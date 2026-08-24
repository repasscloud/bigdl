class Bigdl < Formula
  desc "Command-line downloader for large files with resumable and multi-part downloads"
  homepage "https://github.com/repasscloud/bigdl"
  license "GPL-3.0-only"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/repasscloud/bigdl/releases/download/v0.2.0/bigdl-0.2.0-aarch64-apple-darwin.tar.gz"
      sha256 "1843a32a161ebd94425ebf71002f2a6505dfd7b6dec3963a1b74491a99fdc9a7"
    else
      url "https://github.com/repasscloud/bigdl/releases/download/v0.2.0/bigdl-0.2.0-x86_64-apple-darwin.tar.gz"
      sha256 "add67ef2899314055c4dbfbde908413d556343f9e17f9ab541e6391ea864aa63"
    end
  end

  def install
    bin.install "bigdl"
  end

  test do
    system bin/"bigdl", "--version"
  end
end
