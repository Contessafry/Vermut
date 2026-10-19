# Changelog

All notable changes to Vermut are documented here.

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
