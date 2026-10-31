# Changelog

All notable changes to Vermut are documented here.

## Unreleased

### Added

- Compatibility JSON records **known not working** backend/engine pairs from broken-only reports and no longer marks a `recommended` backend for those titles (e.g. ELDEN RING)
- Gcenx Wine Staging / Devel versions are detected from GitHub releases (11.19 / 11.20 appear when Gcenx publishes them; UI no longer hardcodes 11.18)
- Per-game **Steam overlay** toggle in Game Settings (off by default)
- Library / inspector warning for kernel anti-cheat (Easy Anti-Cheat, BattlEye) from [Are We Anti-Cheat Yet?](https://areweanticheatyet.com/)
- Settings › **x86_64 emulation**: Rosetta 2 (default) or FEX, with runtime detection. FEX needs ARM64 Wine that is not shipping yet — see `docs/FEX.md`
- GOG Galaxy is no longer “Coming soon”: Wine Staging + WineD3D + Qt software / GDI recipe (`docs/GOG.md`)

### Changed

- DXMT catalog lists **stable releases only** (pre-release, draft, and nightly assets are skipped)
- GOG silent setup treats Galaxy on disk as success when Inno never exits (leftover `GalaxyClient.exe` is stopped; 15-minute cap unchanged)
- GOG recipe installs Mesa llvmpipe as `opengl32sw.dll` beside `GalaxyClient.exe` so Qt Quick can create an RHI

### Known

- Engines left by `8b4c701` (DXMT PE in the Wine tree, no `.vermut-wined3d` sidecars) cannot be restored to WineD3D without a reinstall: `restoreIntoEngine` can recognize the overlay bytes, but the original builtin PE is gone. Reinstall the engine.

## 1.2.0 — 2026-10-23

Promotes the QA’d `1.2.0-beta.4` line to stable.

### Added

- In-app update checker with **Stable** / **Beta** channels (Settings › General)
- DXMT multi-version manager (default v0.80) in Settings › Components
- Gcenx Wine Staging / Devel 11.18 engines, downloadable on demand, with GStreamer handling
- D3DMetal manual detection, validation, and install guide
- Per-game settings (Library inspector, ⌥⌘I): Wine engine, graphics backend, DXMT version, and log level, with Automatic inheriting from the store
- Custom Wine bottles: create and manage extra bottles with engine and graphics backend
- Steam library covers for newer apps (@Fenrhir1)
- **Remove Vermut Data…**: selective uninstall of bottles, engines, cache, and preferences (then trash `Vermut.app` yourself)

### Fixed

- Steam launch reliability: first-run restart, window activation, `-applaunch`, Installed gated on the real client
- Quit / cleanup: stop Vermut Wine and bottle Steam processes without SIGKILL of native macOS Steam `ipcserver`
- Onboarding step counter matches the real step count
- Custom bottle Running state stays reactive
- D3DMetal / DXVK unavailable options are rejected; bottle create is gated on name length

## 1.1.2 — 2026-10-20

### Fixed

- Fix a crash at launch on Macs other than the build machine: the SwiftPM resource bundles (colour tokens, brand assets) were never copied into the app, and the generated `Bundle.module` accessor fell back to the build machine's `.build` path and called `fatalError`. Resources are now bundled in `Contents/Resources` and located without `Bundle.module`; a missing `tokens.json` falls back to the built-in palette instead of crashing
- The startup colour-token check is now debug-only and never fatal
- A store no longer shows "Installed" while its installer is still running (the periodic refresh saw the launcher exe the installer writes early)
- Fix Steam not opening on a fresh bottle (wine exited with code 1): a wineserver started by setup or registry tweaks without msync made `steam.exe` fail with `msync_init Failed bootstrap_look_up`. Registry tweaks now use the same sync mode, and Vermut waits for the old wineserver to exit before launching
- A store that fails to launch now shows an error with Retry (which relaunches) instead of staying on "Installed"; set `VERMUT_WINEDEBUG` to capture Wine debug output in the store log
- Fix GOG Galaxy showing "Essential components needed to start GOG GALAXY are missing" right after install: setup auto-started `GalaxyClient.exe /firstRun` while its services were still being registered (service error 1055) and then hung. Vermut now stops only that first-run child, waits for setup and the bottle to settle, and opens GOG from the card
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
