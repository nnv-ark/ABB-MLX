# Homebrew distribution

ABB-MLX ships as a **build-from-source Homebrew formula** in a personal tap.
This route needs no code signing or notarization. (A Homebrew **cask**
shipping a signed/notarized `.app` would be the better long-term UX for a
GUI app, but it depends on roadmap items — `.app` bundle + DMG + Developer ID
notarization — that don't exist yet.)

- App repo: [nnv-ark/ABB-MLX](https://github.com/nnv-ark/ABB-MLX) (public)
- Tap repo: [nnv-ark/homebrew-abb-mlx](https://github.com/nnv-ark/homebrew-abb-mlx) (public)
- Latest tagged release: [`v1.0.0-beta`](https://github.com/nnv-ark/ABB-MLX/releases/tag/v1.0.0-beta)
- Formula: [`abb-mlx.rb`](./abb-mlx.rb) (kept in sync with the tap's `Formula/abb-mlx.rb`)

## Install

A stable tag exists, so plain `brew install` works — `--HEAD` is only needed
if you want unreleased `main`:

```bash
brew tap nnv-ark/abb-mlx
brew trust nnv-ark/abb-mlx      # Homebrew 6+ blocks loading formulae from untrusted taps
brew install abb-mlx            # or: brew install --HEAD abb-mlx for unreleased main
abb-mlx                         # launches the menu-bar app
```

## Cutting a new release

When `VERSION` bumps (or enough has landed on `main` to warrant a new stable
tag):

```bash
cd "path/to/ABB-MLX"
git tag vX.Y.Z && git push origin vX.Y.Z
gh release create vX.Y.Z --generate-notes   # add --prerelease for a beta

# Get the tarball sha256:
curl -sL https://github.com/nnv-ark/ABB-MLX/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
```

Then update `url` / `version` / `sha256` in **both**
[`packaging/homebrew/abb-mlx.rb`](./abb-mlx.rb) (this repo, for reference) and
[`homebrew-abb-mlx/Formula/abb-mlx.rb`](https://github.com/nnv-ark/homebrew-abb-mlx/blob/main/Formula/abb-mlx.rb)
(the tap — this is the copy Homebrew actually reads), commit, and push both.
They should stay byte-identical; a quick `diff` before committing catches
drift.

## Notes / gotchas

- **Apple Silicon only.** MLX has no x86_64 path; the formula pins `arch: :arm64`.
- **Full Xcode required to build**, not just Command Line Tools — MLX compiles
  Metal shaders. Hence `depends_on xcode: [..., :build]`.
- **Resource bundles.** The build emits `*.bundle` dirs (MLX's `mlx.metallib`,
  swift-transformers tokenizer data, NIO) next to the binary; the formula
  installs them into `libexec` and symlinks the launcher into `bin` so
  `Bundle.module` resolves them. A bare `bin.install` of the executable would
  crash at launch.
- **First build is heavy** — compiling mlx-swift from source takes minutes and
  several GB. A cask (prebuilt binary) would avoid this; revisit once the
  `.app`/DMG/notarization roadmap lands.
- **Test block** only asserts installation, since the app is an `LSUIElement`
  GUI with no CLI flags. Adding a `--version`/`--health` flag to `ABBMLXApp`
  would enable a real `brew test`.
- **No license file yet** — the formula's `license` line is commented out.
  Add a real SPDX identifier (e.g. `license "MIT"`) once one is chosen; a
  public Homebrew tap without a license is a rough edge worth fixing.
