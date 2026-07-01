class AbbMlx < Formula
  desc "Menu-bar app serving local MLX LLMs via an OpenAI-compatible HTTP API"
  homepage "https://github.com/nnv-ark/ABB-MLX"
  url "https://github.com/nnv-ark/ABB-MLX/archive/refs/tags/v1.0.0-beta.tar.gz"
  version "1.0.0-beta"
  sha256 "92531b213f3e344481c734a09d74e9d2dd39722652ec2ca185fe691a96dbe51c"
  # TODO: the project README carries only a copyright line, not an OSI license.
  # Set a real SPDX identifier before publishing a public tap, e.g.:
  # license "MIT"

  head "https://github.com/nnv-ark/ABB-MLX.git", branch: "main"

  # MLX is Apple-Silicon only; the package targets macOS 14 (Sonoma); and
  # compiling MLX's Metal shaders needs the full Xcode toolchain, not just CLT.
  depends_on xcode: ["15.0", :build]
  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    system "swift", "build", "--disable-sandbox", "--configuration", "release"

    # ABBMLXApp loads its Metal shaders (mlx.metallib) and tokenizer data
    # through Bundle.module, which resolves relative to the executable. The
    # resource bundles emitted next to the binary in .build/release must
    # therefore be installed alongside it. Stage everything in libexec and
    # expose a `abb-mlx` launcher symlink in bin (macOS resolves the symlink
    # to its real path, so Bundle.module still finds the bundles in libexec).
    release = ".build/release"
    libexec.install "#{release}/ABBMLXApp"
    libexec.install Dir["#{release}/*.bundle"]
    libexec.install Dir["#{release}/*.dylib"]
    bin.install_symlink libexec/"ABBMLXApp" => "abb-mlx"
  end

  def caveats
    <<~EOS
      abb-mlx is a menu-bar app (LSUIElement) — launching it adds a CPU icon to
      the menu bar; it has no Dock icon and no window. Start it with:
        abb-mlx
      Click the menu-bar icon; if no model is installed yet, pick one from the
      built-in download list, then click Start once it finishes.

      To wire it into Xcode: Settings -> Coding Intelligence -> Chat ->
      Add a Chat Provider... -> Localhost, URL http://localhost:8080.

      First install builds mlx-swift from source (Metal shader compilation) —
      expect several minutes and a few GB of build space.
    EOS
  end

  test do
    # It is a GUI menu-bar app with no CLI flags, so it can't be exercised
    # headlessly. Verify the binary and its launcher symlink were installed.
    assert_path_exists bin/"abb-mlx"
    assert_path_exists libexec/"ABBMLXApp"
    assert_predicate bin/"abb-mlx", :executable?
  end
end
