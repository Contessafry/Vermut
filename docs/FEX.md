# FEX vs Rosetta 2

Vermut’s default x86_64 path is **Rosetta 2**. That matches the engines we can download today.

## What CrossOver Preview does

CodeWeavers’ CrossOver Preview (2026) ships a **universal** build:

- **Intel Wine + Rosetta 2** on macOS older than 26.5, or when the user stays on the Intel bottle path
- **ARM64 Wine + FEX** on macOS 26.5+ (native Wine, FEX translates x86_64/i386 Windows PE)

FEX here is CodeWeavers’ macOS port of [FEX-Emu](https://github.com/FEX-Emu/FEX), not a drop-in for x86_64 Wine. You cannot point Gcenx `*-osx64` Wine at FEX and skip Rosetta.

Sources:

- [CrossOver Preview: The right to bear ARM64 on Mac](https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac)
- [What’s in and what’s out for CrossOver 27](https://www.codeweavers.com/blog/mjohnson/2026/06/11/whats-in-and-whats-out-for-crossover-27)

## What Vermut implements

Settings › General › **x86_64 emulation**:

| Mode | Behaviour |
| --- | --- |
| **Rosetta 2** (default) | Existing Steam hint `ROSETTA_ADVERTISE_AVX=1`. All current engines. |
| **FEX** | Used only when an ARM64 `wine` binary **and** FEX libraries are present. Otherwise the UI explains the gap and launch stays on Rosetta. |

Detection looks for `FEXInterpreter` / `libFEXCore.dylib` under:

- `~/Library/Application Support/Vermut/engines/fex`
- `/opt/fex-emu`
- CrossOver / CrossOver Preview `SharedSupport` FEX folders

Wine architecture is read from the Mach-O CPU type (`x86_64` vs `arm64`).

## What remains (needs a Mac + an ARM64 engine)

1. **No public ARM64 Wine tarball** in [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds) (assets are `*-osx64.tar.xz`) or current Vermut Wine / grapple-wine.
2. **No redistributable FEX-for-macOS** we can vendor. CrossOver’s FEX is part of their Preview app.
3. Bottles created under Rosetta/x86_64 Wine are **not** convertible to ARM64 (same limitation as CrossOver).
4. DXMT on ARM64 Wine is a separate packaging problem (CrossOver Preview ships ARM64 DXMT).

When an ARM64 engine appears (Gcenx, grapple, or a Vermut build), drop FEX libs in `engines/fex`, install the ARM64 Wine tree, and the existing setting will switch launch env (`FEX_ROOTFS`, `FEX_INTERPRETER`) without another schema change.

Until then, leave the control on **Rosetta 2**.
