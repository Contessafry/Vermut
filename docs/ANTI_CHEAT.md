# Kernel anti-cheat warnings

Library tiles and Game Settings show a warning when a title uses **Easy Anti-Cheat** or **BattlEye**. Those are kernel-mode on Windows and almost never run under Wine on macOS. Vermut does not bypass anti-cheat.

## Source

Primary dataset: **[Are We Anti-Cheat Yet?](https://areweanticheatyet.com/)**  
Upstream file: [`games.json`](https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet/blob/master/games.json) in [AreWeAntiCheatYet/AreWeAntiCheatYet](https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet).

The site is the usual crowd-sourced reference for EAC/BattlEye vs Proton/Wine. Steam AppIDs in that file are what we match on.

## What we ship

`Sources/CaskLauncherCore/kernel-anticheat.json` is a **compact extract** (generated 2026-10-26):

- Only titles whose `anticheats` include Easy Anti-Cheat or BattlEye
- Only entries that have a Steam and/or Epic store id
- Fields: `steamId`, `epicId`, `name`, `anticheats`, `linuxStatus`, `slug`

`linuxStatus` is Proton/Linux status from AreWeAntiCheatYet (`Supported`, `Running`, `Broken`, `Denied`, …). **Supported on Linux does not mean it will run in Vermut.** We still warn.

Lookup order: Steam AppID → Epic id → normalized game name.

## Refreshing the extract

```bash
curl -fsSL https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/master/games.json -o /tmp/awacy-games.json
# filter EAC/BattlEye + store ids into Sources/CaskLauncherCore/kernel-anticheat.json
```

Keep the `source` / `sourceUrl` / `homepage` fields so the in-app help stays honest.

## What this is not

- Not a block list (you can still press Play)
- Not VAC / Ricochet / GameGuard (those are different)
- Not a live network fetch at launch (bundled snapshot only)
