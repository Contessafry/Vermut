# Changelog

All notable changes to Vermut are documented here.

## 1.1.2 — 2026-10-20

### Fixed

- Fix a crash at launch on Macs other than the build machine: the SwiftPM resource bundles (colour tokens, brand assets) were never copied into the app, and the generated `Bundle.module` accessor fell back to the build machine's `.build` path and called `fatalError`. Resources are now bundled in `Contents/Resources` and located without `Bundle.module`; a missing `tokens.json` falls back to the built-in palette instead of crashing
- The startup colour-token check is now debug-only and never fatal
- `build.sh` now fails if a resource bundle is missing, and runs a smoke test that launches the app from a temporary folder with `.build` hidden

## 1.1.1 — 2026-10-20

### Fixed

- Fix "Vermut is damaged and can't be opened" when the DMG is downloaded from a browser: the app bundle now gets a complete ad-hoc signature (sealed resources, bound Info.plist), and the build fails if `codesign --verify --deep --strict` does not pass

## 1.1.0 — 2026-10-20

### Added

- Community compatibility reports: after a play session of 5+ minutes (or an early exit), a feedback banner asks how the game ran and opens a prefilled GitHub issue (no account data leaves the Mac unless you submit it)
- Library compatibility badges (Works / Mixed / Issues) built from community reports, published on the `compat-data` branch
- Settings → Compatibility reports: toggle to turn the feedback prompts off
- GitHub workflow that validates reports and aggregates them into `compat/compatibility.json`
- `install.sh`: one-line terminal installer (`curl -fsSL https://raw.githubusercontent.com/Contessafry/Vermut/main/install.sh | bash`) that installs the latest release into `/Applications` without Gatekeeper quarantine

## 1.0.0 — 2026-10-19

First public release.

### Added

- Native macOS 14+ app for Apple Silicon: **Pour. Click. Play.**
- Steam bottle: official `SteamSetup.exe`, Wine 11 + DXMT, CEF-safe launch flags
- GOG Galaxy bottle: official offline installer, WineD3D
- Epic Games via **Legendary** 0.21.1 (beta): native macOS binary, checksum, in-app login, library, install, launch
- Wine engines: Vermut Wine 11 (DXMT build), Wine Staging 11, Wine Devel 11
- Per-bottle graphics: DXMT, DXVK + MoltenVK, WineD3D, optional D3DMetal when GPTK is already installed
- Library, downloads, bottle settings, logs, Run .exe
- Unsigned `Vermut.app` via `./build.sh` and `Vermut-<version>.dmg` via `./scripts/make-dmg.sh`

### Notes

- The app is not notarized. First launch needs right-click → Open or `xattr -dr com.apple.quarantine`.
- Epic is a beta path. It does not install the Epic Games Launcher.
- DXVK bottles use Wine Staging because the DXMT Wine 11 build has no Vulkan loader.
- Game compatibility is not guaranteed.
