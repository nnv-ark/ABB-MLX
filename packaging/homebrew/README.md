# Homebrew distribution

ABB-MLX ships as a **build-from-source Homebrew formula** in a personal tap.
This route needs no code signing or notarization and works today. (A Homebrew
**cask** shipping a signed/notarized `.app` is the better long-term UX for a
GUI app, but it depends on the roadmap items — `.app` bundle + DMG + Developer
ID notarization — that don't exist yet.)

The formula lives at [`abb-mlx.rb`](./abb-mlx.rb). Replace `OWNER` with your
GitHub owner before publishing.

## 1. Push ABB-MLX to GitHub

The formula's `head` builds from your repo, so it needs a remote first:

```bash
cd "path/to/ABB-MLX"
git add -A && git commit -m "Initial commit"
gh repo create OWNER/ABB-MLX --private --source=. --remote=origin --push
# (drop --private for a public repo)
```

## 2. Create the tap repo

A Homebrew tap is a GitHub repo named `homebrew-<tap>`:

```bash
mkdir -p homebrew-abb-mlx/Formula
cp packaging/homebrew/abb-mlx.rb homebrew-abb-mlx/Formula/abb-mlx.rb
# edit Formula/abb-mlx.rb: set OWNER
cd homebrew-abb-mlx
git init -b main && git add -A && git commit -m "abb-mlx formula"
gh repo create OWNER/homebrew-abb-mlx --public --source=. --remote=origin --push
```

## 3. Install

```bash
brew tap OWNER/abb-mlx           # adds OWNER/homebrew-abb-mlx
brew trust OWNER/abb-mlx         # Homebrew 6+ blocks loading formulae from untrusted taps
brew install --HEAD abb-mlx      # builds from main
abb-mlx                          # launches the menu-bar app
```

`--HEAD` is required until you cut a tagged stable release (below), because the
formula has no stable `url` yet.

## 4. (Optional) Cut a stable release so `--HEAD` isn't needed

```bash
cd "path/to/ABB-MLX"
git tag v1.0.0-beta && git push origin v1.0.0-beta
gh release create v1.0.0-beta --generate-notes

# Get the tarball sha256:
curl -sL https://github.com/OWNER/ABB-MLX/archive/refs/tags/v1.0.0-beta.tar.gz | shasum -a 256
```

Then in `Formula/abb-mlx.rb`, uncomment the `url` / `sha256` / `version` block
and paste the sha256. Commit and push the tap. Users can now run plain
`brew install abb-mlx`.

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
