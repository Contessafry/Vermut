# Third-Party Components

Vermut downloads and uses several open-source components. This document lists all external components, their licenses, and where they are obtained from.

## Components Downloaded at Runtime

### Wine (Windows Compatibility Layer)

**What it is**: Wine implements Windows APIs on Unix-like systems, allowing Windows applications to run on macOS.

**Versions used**:
- **grapple-wine** (default): CrossOver 26.3 / Wine 11, LGPL. winemac exports the Metal views DXMT needs.
- Wine Staging 11.18 and Wine Devel from Gcenx `macOS_Wine_builds` (fallback)

**License**: LGPL 2.1 or later  
**Wine Copyright**: Copyright (c) 1993-2024 the Wine project authors  
**License URL**: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html

Wine itself is LGPL, and we download it as a separate component (not statically linked). Users are free to replace the Wine engine with any compatible version.

**grapple-wine**  
**Downloaded from**: GitHub Releases (`MartijnBud/grapple-releases`), currently pinned fallback `v0.2.5-beta.1` asset `grapple-wine-1.0.2.tar.xz`  
**Source / LGPL corresponding source**: https://github.com/MartijnBud/grapple-releases  
**CrossOver LGPL source releases**: https://www.codeweavers.com/crossover/source  

**Wine Staging / Devel**  
**Source**: https://github.com/Gcenx/macOS_Wine_builds  
**Downloaded from**: GitHub Releases (`Gcenx/macOS_Wine_builds`)

### DXMT (DirectX to Metal Translation Layer)

**What it is**: DXMT translates DirectX 10/11 API calls to Apple's Metal graphics API, enabling Windows games to run with native graphics performance on macOS.

**Default version**: v0.80 (users can install and switch between releases side by side)  
**License**: LGPL 2.1+ **from v0.80 onward** (earlier tags may use a different licence; Vermut defaults to and recommends v0.80+)  
**Source**: https://github.com/3Shain/dxmt  
**Downloaded from**: GitHub Releases (3Shain/dxmt), SHA-256 verified when the release publishes a digest  

**DXMT Copyright**: Copyright (c) 2024–2026 DXMT Contributors  
**License URL**: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html  

Vermut stores each DXMT build under `Application Support/Vermut/engines/dxmt/versions/<tag>/` and keeps an active-version pointer so users can roll back without re-downloading.

### DXVK + MoltenVK (Optional - DirectX to Vulkan to Metal)

**What it is**: DXVK translates DirectX to Vulkan, and MoltenVK translates Vulkan to Metal. This is an alternative graphics layer.

**DXVK Version**: 2.4.1  
**DXVK License**: Zlib License  
**DXVK Source**: https://github.com/doitsujin/dxvk (macOS builds from Gcenx/DXVK-macOS)  
**Downloaded from**: GitHub Releases (Gcenx/DXVK-macOS)

**DXVK Copyright**: Copyright (c) 2017-2024 Philip Rebohle, Joshua Ashton, and contributors

**Zlib License Text**:
```
This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.
```

**MoltenVK License**: Apache License 2.0  
**MoltenVK Source**: https://github.com/KhronosGroup/MoltenVK  
**MoltenVK Copyright**: Copyright (c) 2015-2024 The Brenwill Workshop Ltd.

### Legendary (Epic Games client)

**What it is**: A free, open-source replacement for the Epic Games Launcher. Vermut downloads the official macOS arm64 binary and runs it **natively** (not under Wine). Config lives in the Epic bottle folder (`LEGENDARY_CONFIG_PATH`).

**Version**: 0.21.1 (GitHub latest, pinned fallback)  
**License**: GNU General Public License v3.0  
**Source**: https://github.com/derrod/legendary (canonical GitHub org: `legendary-gl/legendary`)  
**Downloaded from**: GitHub Releases (`legendary_macOS_arm64`), SHA-256 verified  

Legendary is executed as a separate process. Vermut does not statically link it.

**Legendary Copyright**: Copyright (c) Legendary contributors  

### Game Store Installers

Vermut downloads official installers from the respective store vendors:

- **Steam**: Downloaded from https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe  
  Copyright © Valve Corporation

- **Epic Games**: Vermut does **not** install the official Epic Games Launcher. Epic authentication, library listing, installs and launches go through **Legendary** (see below). Game files still come from Epic's CDN under your Epic account.  
  Copyright © Epic Games, Inc.

- **GOG Galaxy**: Full offline Inno Setup installer from `content-system.gog.com` (`setup_galaxy_*.exe`, resolved via `https://remote-config.gog.com/components/webinstaller?component_version=2.0.0`). Not the `GOG_Galaxy_2.0.exe` web stub.  
  Copyright © GOG sp. z o.o.

These are official, freely available installers from the respective companies. Vermut does not modify, crack, or circumvent any protections in these installers. Users must agree to each store's terms of service when using their software.

### Store logo glyphs (in-app)

Official Steam, Epic Games and GOG.com marks used on store tiles and the sidebar, as Simple Icons templates rasterized to PNG@1x/@2x/@3x plus PDF (`Sources/CaskLauncherCore/BrandAssets/`, copied into `Vermut.app/Contents/Resources/BrandAssets` by `./build.sh`). Source SVGs remain in `Resources/simple-icons/`.

### Vermut wordmark (in-app)

Outlined “Vermut” in **Bricolage Grotesque** (OFL), wght 700 / wdth 85 / opsz 96, shipped as original (not template) PDFs: dark `#09090B` for light mode (`vermut-wordmark`) and white for dark mode (`vermut-wordmark-white`). Source SVGs and the OFL text are in `Resources/brand/`; regenerate with `scripts/generate-vermut-wordmark.py`.

**Source**: https://github.com/google/fonts/tree/main/ofl/bricolagegrotesque  
**License**: SIL Open Font License 1.1 (`Resources/brand/BricolageGrotesque-OFL.txt`)

**Source**: https://github.com/simple-icons/simple-icons  
**License**: CC0 1.0 Universal  
**Icons**: `steam`, `epicgames`, `gogdotcom`

## Apple D3DMetal (NOT Included)

**Important**: Apple's D3DMetal translation layer (part of Game Porting Toolkit) is **NOT** included, bundled, or downloaded by Vermut. It is proprietary Apple software.

If a user has manually installed Apple's Game Porting Toolkit on their system, Vermut can detect it and allow the user to select it as an optional graphics backend for DirectX 12 games. This is similar to how an application might detect and use system-provided frameworks.

**Apple GPTK License**: Proprietary (Apple)  
**Installation**: User must install separately via Apple Developer portal

## License Compatibility

Vermut itself is MIT-licensed (`LICENSE`). All components it downloads are either:
- LGPL (Wine, DXMT) - Compatible with MIT when dynamically linked/downloaded separately
- GPLv3 (Legendary) - Run as a separate process, not linked. The app bundle does not ship the Legendary binary; it is downloaded at runtime.
- Zlib (DXVK) - Compatible with MIT
- Apache 2.0 (MoltenVK) - Compatible with MIT
- CC0 (Simple Icons) and SIL OFL 1.1 (Bricolage Grotesque) - bundled glyphs/wordmark

Vermut does not statically link any LGPL code. All LGPL components are downloaded as separate binaries and executed as separate processes, which is explicitly permitted by the LGPL.

## Component Versions and Updates

The specific versions and download URLs are defined in the source code:
- `Sources/CaskLauncherCore/Models.swift` - Wine engine versions
- `Sources/CaskLauncherCore/EngineManager.swift` - Download URLs and versions

Users can verify downloaded component integrity by checking:
1. All downloads are from official GitHub releases or vendor CDN
2. Downloads use HTTPS
3. Where available, SHA-256 checksums are verified (components.json manifest)

## Questions

If you have questions about the licensing of any component, please open an issue on GitHub.

## Disclaimer

Vermut is an independent open-source project and is not affiliated with, endorsed by, or sponsored by:
- CodeWeavers (CrossOver)
- Valve Corporation (Steam)
- Epic Games (Epic Games Store)
- GOG sp. z o.o. (GOG Galaxy)
- Apple Inc. (macOS, Metal, Game Porting Toolkit)
- The Wine project

All trademarks are property of their respective owners.
