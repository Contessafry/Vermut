# GOG Galaxy configuration

## Why it was “Coming soon”

GOG Galaxy’s Qt UI tries to create a D3D11 renderer. Under DXMT/DXVK that window stayed blank, so Stores hid the install button.

## Recipe in this build

| Knob | Value |
| --- | --- |
| Engine | **Wine Staging** (Gcenx, latest detected release) |
| Graphics | **WineD3D** (forced) |
| DLL overrides | `d3d10core,d3d11,d3d12,dxgi,winemetal=builtin` |
| Wine Direct3D | `renderer=gdi` |
| Qt / GL | `QT_OPENGL=software`, `QT_QUICK_BACKEND=software`, `QSG_RHI_BACKEND=software`, `LIBGL_ALWAYS_SOFTWARE=1`, `GALLIUM_DRIVER=llvmpipe` |
| Software renderer | Mesa 26.2.5 `opengl32.dll` copied as `opengl32sw.dll` + `libgallium_wgl.dll` next to `GalaxyClient.exe` |
| Args | `--disable-gpu --disable-gpu-compositing` |
| Installer | Official offline `setup_galaxy_*.exe` (web stub rejected), Inno `/VERYSILENT /CLOSEAPPLICATIONS /FORCECLOSEAPPLICATIONS` |
| Setup hang | Inno still launches Galaxy after files land. Vermut stops every `GalaxyClient.exe` in the prefix. Payload on disk is success even if setup.exe never exits. 15-minute cap is unchanged. |
| First-run | Leftover Galaxy during setup (with or without `/firstRun`) is stopped so Inno can finish |

New GOG bottles pin Staging. Install downloads Staging if needed. Play / Open GOG asks you to download it when it is missing.

## Install path that works without Galaxy UI

If Galaxy is still blank on a given Mac:

1. Keep the GOG bottle (WineD3D + Staging).
2. Run official GOG **Windows offline installers** (`setup_*.exe`) with Vermut’s Run .exe / custom bottle tools, targeting the GOG prefix.
3. Games land in `drive_c/GOG Games` or `Program Files (x86)/GOG Galaxy/Games`.
4. Library already parses `goggame-*.info` from those folders.

There is no Heroic/`gogdl` client in this change (Legendary-style). Library **Play** still opens Galaxy, not a per-title exe.

## What was tested

| Check | Where | Result |
| --- | --- | --- |
| Silent installer URL / filename validation | Linux VM, unit tests | Pass |
| Hung Inno + payload accepted (no `installerTimedOut`) | Linux VM, unit tests | Pass |
| Recipe supplies `opengl32sw.dll` + `libgallium_wgl.dll` | Linux VM, unit tests | Pass |
| Launch env / argv / GDI registry | Linux VM, unit tests | Pass |
| Coming-soon gate removed | Linux VM, unit tests | Pass |
| Staging download + prefix create | WineManager + EngineManager | Code path only |
| Galaxy window actually paints | **Not tested** | Needs Apple Silicon Mac QA |
| Offline `setup_game.exe` → `goggame-*.info` in Library | **Not tested** | Needs Mac QA |
| Login / cloud / overlay inside Galaxy | **Not tested** | Needs Mac QA |

Galaxy's `Failed to create D3D11 device … 0x80004005` under this recipe is Qt's first RHI attempt against Wine GDI, not the DXMT-in-engine placement bug. The fatal path is the missing `opengl32sw.dll` fallback.

If Galaxy is still blank after Mac QA, next step is a native `gogdl` path (same idea as Legendary for Epic), not more D3D backends.
