import XCTest
@testable import CaskLauncherCore

final class SteamRecipeTests: XCTestCase {

    func testLegacyEngineNamesResolveToGrappleWine() {
        XCTAssertEqual(WineEngine.resolved(from: "grapple-wine"), .grappleWine)
        XCTAssertEqual(WineEngine.resolved(from: "staging"), .staging)
        XCTAssertEqual(WineEngine.resolved(from: "devel"), .devel)
        XCTAssertEqual(WineEngine.resolved(from: "Wine 11 (CrossOver)"), .grappleWine)
        XCTAssertEqual(WineEngine.resolved(from: "Wine Staging"), .grappleWine)
        XCTAssertEqual(WineEngine.resolved(from: ""), .grappleWine)
    }

    func testAppConfigurationMigratesLegacyDefaultEngine() {
        var config = AppConfiguration(defaultEngine: "Wine 11 (CrossOver)")
        XCTAssertTrue(config.migrateLegacyEngineIfNeeded())
        XCTAssertEqual(config.defaultEngine, WineEngine.grappleWine.rawValue)
        XCTAssertFalse(config.migrateLegacyEngineIfNeeded())

        var staging = AppConfiguration(defaultEngine: WineEngine.staging.rawValue)
        XCTAssertFalse(staging.migrateLegacyEngineIfNeeded())
        XCTAssertEqual(staging.defaultEngine, "staging")
    }

    func testSteamLaunchUsesConfiguredDefaultEngineNotBottle() {
        XCTAssertEqual(
            StoreLaunchRecipe.engine(
                for: .steam,
                defaultEngine: "grapple-wine",
                bottleEngine: "staging"
            ),
            .grappleWine
        )
        XCTAssertEqual(
            StoreLaunchRecipe.engine(
                for: .steam,
                defaultEngine: "Wine 11 (CrossOver)",
                bottleEngine: "staging"
            ),
            .grappleWine
        )
        XCTAssertEqual(
            StoreLaunchRecipe.engine(
                for: .epic,
                defaultEngine: "grapple-wine",
                bottleEngine: "staging"
            ),
            .staging
        )
        XCTAssertEqual(
            StoreLaunchRecipe.engine(
                for: .gog,
                defaultEngine: "grapple-wine",
                bottleEngine: "staging"
            ),
            .staging
        )
    }

    func testLaunchLogLineIncludesEngineAndWinePath() {
        let wine = URL(fileURLWithPath: "/engines/grapple-wine/grapple-wine/bin/wine")
        let server = URL(fileURLWithPath: "/engines/grapple-wine/grapple-wine/bin/wineserver")
        let line = StoreLaunchRecipe.launchLogLine(
            store: .steam,
            engine: .grappleWine,
            wine: wine,
            wineserver: server
        )
        XCTAssertTrue(line.contains("engine=grapple-wine"))
        XCTAssertTrue(line.contains("wine=\(wine.path)"))
        XCTAssertTrue(line.contains("wineserver=\(server.path)"))
        XCTAssertTrue(line.contains("steam"))
        XCTAssertFalse(line.contains("engines/staging"))
    }

    func testLaunchEnvironmentSummaryListsWineVarsWithoutDumpingFullPATH() {
        let engineRoot = URL(fileURLWithPath: "/engines/grapple-wine")
        let wine = URL(fileURLWithPath: "/engines/grapple-wine/bin/wine")
        let wineBin = wine.deletingLastPathComponent().path
        let env: [String: String] = [
            "WINEPREFIX": "/bottles/steam/prefix",
            "WINELOADER": wine.path,
            "WINESERVER": "/engines/grapple-wine/bin/wineserver",
            "WINEDLLPATH": "/engines/grapple-wine/lib/wine",
            "WINEDEBUG": "-all",
            "WINEESYNC": "1",
            "WINEMSYNC": "1",
            "WINEDLLOVERRIDES": "gameoverlayrenderer,gameoverlayrenderer64=d",
            "PATH": "\(wineBin):/usr/bin:/bin",
            "HOME": "/Users/secret",
            "TOKEN": "should-not-appear"
        ]
        let line = StoreLaunchRecipe.launchEnvironmentSummary(
            engineRoot: engineRoot,
            wine: wine,
            environment: env
        )
        XCTAssertTrue(line.hasPrefix("Vermut: launch-env "))
        XCTAssertTrue(line.contains("engineRoot=\(engineRoot.path)"))
        XCTAssertTrue(line.contains("wine=\(wine.path)"))
        XCTAssertTrue(line.contains("WINEPREFIX=/bottles/steam/prefix"))
        XCTAssertTrue(line.contains("WINEESYNC=1"))
        XCTAssertTrue(line.contains("PATH=wine-bin-first+2-more"))
        XCTAssertFalse(line.contains("/usr/bin"))
        XCTAssertFalse(line.contains("TOKEN"))
        XCTAssertFalse(line.contains("should-not-appear"))
        XCTAssertFalse(line.contains("HOME="))
    }

    func testSummarizeLaunchPATHDetectsWineBinNotFirst() {
        let summary = StoreLaunchRecipe.summarizeLaunchPATH(
            "/usr/bin:/engines/grapple-wine/bin",
            wineBin: "/engines/grapple-wine/bin"
        )
        XCTAssertEqual(summary, "wine-bin-not-first first=/usr/bin")
    }

    func testSteamLaunchArgumentsAndEnvironment() {
        let wineLib = URL(fileURLWithPath: "/engines/grapple-wine/grapple-wine/lib/wine")
        let steam = URL(fileURLWithPath: "/bottles/steam/prefix/drive_c/Program Files (x86)/Steam/steam.exe")

        let recipe = StoreLaunchRecipe.build(store: .steam, executable: steam, wineLibDir: wineLib)

        XCTAssertEqual(
            recipe.arguments,
            ["steam.exe", "-no-cef-sandbox", "-cef-disable-gpu", "-noverifyfiles"]
        )
        XCTAssertEqual(recipe.workingDirectory, steam.deletingLastPathComponent().path)
        XCTAssertEqual(recipe.environment["WINEESYNC"], "1")
        XCTAssertEqual(recipe.environment["WINEMSYNC"], "1")
        XCTAssertEqual(recipe.environment["ROSETTA_ADVERTISE_AVX"], "1")
        XCTAssertEqual(recipe.environment["CX_FWD_COMPAT_GL_CTX"], "1")
        XCTAssertEqual(recipe.environment["WINEDEBUG"], "-all")
        XCTAssertEqual(recipe.environment["WINEDLLPATH"], wineLib.path)
        XCTAssertEqual(
            recipe.environment["WINEDLLOVERRIDES"],
            StoreLaunchRecipe.steamOverlayDisableOverride
        )
        XCTAssertEqual(recipe.environment["SteamNoOverlay"], "1")
        XCTAssertNil(recipe.environment["WINE_D3D_CONFIG"])
        XCTAssertFalse((recipe.environment["WINEDLLOVERRIDES"] ?? "").contains("winevulkan"))
        XCTAssertNil(recipe.environment["steamwebhelper.exe"])
    }

    func testSteamOverlayCanBeEnabledPerGame() {
        let wineLib = URL(fileURLWithPath: "/engines/grapple-wine/lib/wine")
        let steam = URL(fileURLWithPath: "/bottles/steam/prefix/drive_c/Program Files (x86)/Steam/steam.exe")
        let recipe = StoreLaunchRecipe.build(
            store: .steam,
            executable: steam,
            wineLibDir: wineLib,
            steamAppId: "570",
            steamOverlayEnabled: true
        )
        XCTAssertNil(recipe.environment["WINEDLLOVERRIDES"])
        XCTAssertNil(recipe.environment["SteamNoOverlay"])
    }

    func testEpicLaunchDoesNotUseSteamFlags() {
        let wineLib = URL(fileURLWithPath: "/engines/staging/lib/wine")
        let exe = URL(fileURLWithPath: "/prefix/drive_c/Games/Fortnite/Fortnite.exe")
        let recipe = StoreLaunchRecipe.build(store: .epic, executable: exe, wineLibDir: wineLib)
        XCTAssertEqual(recipe.arguments, [])
        XCTAssertFalse(recipe.arguments.contains("-SkipBuildPatchPrereq"))
        XCTAssertFalse(recipe.arguments.contains("-OpenGL"))
        XCTAssertFalse(recipe.arguments.contains("-cef-disable-gpu"))
        XCTAssertFalse(recipe.arguments.contains("--disable-gpu"))
        XCTAssertFalse(recipe.arguments.contains("steam.exe"))
        XCTAssertFalse(recipe.arguments.contains("-no-cef-sandbox"))
        XCTAssertNil(recipe.environment["WINEESYNC"])
        XCTAssertNil(recipe.environment["CX_FWD_COMPAT_GL_CTX"])
        XCTAssertNil(recipe.environment["WINE_D3D_CONFIG"])
        XCTAssertNil(recipe.environment["WINEDLLOVERRIDES"])
        XCTAssertNil(recipe.workingDirectory)
        XCTAssertEqual(recipe.environment["WINEARCH"], "win64")
        XCTAssertEqual(recipe.environment["WINEDLLPATH"], wineLib.path)
        XCTAssertEqual(recipe.environment["WINEDEBUG"], StoreLaunchRecipe.epicWineDebug)
        XCTAssertNotEqual(recipe.environment["WINEDEBUG"], "-all")
    }

    func testGOGLaunchDisablesCEFGPU() {
        let wineLib = URL(fileURLWithPath: "/engines/grapple-wine/lib/wine")
        let exe = URL(fileURLWithPath: "/prefix/drive_c/Program Files (x86)/GOG Galaxy/GalaxyClient.exe")
        let recipe = StoreLaunchRecipe.build(store: .gog, executable: exe, wineLibDir: wineLib)
        XCTAssertEqual(
            recipe.arguments,
            ["GalaxyClient.exe"] + GOGRecipe.launchArguments
        )
        XCTAssertEqual(recipe.environment["WINEDLLOVERRIDES"], GOGRecipe.dllOverrides)
        XCTAssertEqual(recipe.environment["QT_OPENGL"], "software")
        XCTAssertEqual(recipe.environment["QT_QUICK_BACKEND"], "software")
        XCTAssertEqual(recipe.environment["QSG_RHI_BACKEND"], "software")
        XCTAssertEqual(recipe.environment["LIBGL_ALWAYS_SOFTWARE"], "1")
        XCTAssertNil(recipe.environment["WINE_D3D_CONFIG"])
        XCTAssertFalse((recipe.environment["WINEDLLOVERRIDES"] ?? "").contains("winevulkan"))
        XCTAssertNil(recipe.environment["WINEESYNC"])
        XCTAssertEqual(recipe.workingDirectory, exe.deletingLastPathComponent().path)
    }

    func testDXMTNativeOnlyOnGrappleWine() {
        XCTAssertTrue(WineEngine.grappleWine.supportsDXMT)
        XCTAssertFalse(WineEngine.staging.supportsDXMT)
        XCTAssertFalse(WineEngine.devel.supportsDXMT)

        let grapple = DllOverridePolicy.globalGraphicsOverrides(engine: .grappleWine, backend: .dxmt)
        XCTAssertTrue(grapple.isEmpty, "grapple-wine must not set global D3D overrides")

        let stagingDXMT = DllOverridePolicy.globalGraphicsOverrides(engine: .staging, backend: .dxmt)
        XCTAssertEqual(stagingDXMT["d3d11"], "builtin")
        XCTAssertEqual(stagingDXMT["dxgi"], "builtin")
        XCTAssertEqual(stagingDXMT["winemetal"], "builtin")

        let stagingWined3d = DllOverridePolicy.globalGraphicsOverrides(engine: .staging, backend: .wined3d)
        XCTAssertEqual(stagingWined3d["d3d11"], "builtin")

        XCTAssertFalse(DllOverridePolicy.usesNativeDXMT(engine: .staging, backend: .dxmt))
        XCTAssertTrue(DllOverridePolicy.usesNativeDXMT(engine: .grappleWine, backend: .dxmt))
        XCTAssertFalse(DllOverridePolicy.usesNativeDXMT(engine: .grappleWine, backend: .wined3d))
        XCTAssertTrue(DllOverridePolicy.usesNativeDXMT(engine: .grappleWine, backend: .dxmt, store: .epic))
        XCTAssertFalse(DllOverridePolicy.usesNativeDXMT(engine: .grappleWine, backend: .dxmt, store: .gog))

        let epicGlobals = DllOverridePolicy.globalGraphicsOverrides(
            engine: .staging,
            backend: .dxvk,
            store: .epic
        )
        XCTAssertEqual(epicGlobals["d3d11"], "native")
        XCTAssertEqual(epicGlobals["dxgi"], "native")
        XCTAssertEqual(epicGlobals["vulkan-1"], "builtin")
        XCTAssertEqual(epicGlobals["winevulkan"], "builtin")

        let epicWrites = DllOverridePolicy.registryWrites(
            engine: .staging,
            backend: .dxvk,
            store: .epic
        ).compactMap(\.added)
        XCTAssertTrue(epicWrites.contains {
            $0.key == DllOverridePolicy.globalDllOverridesKey && $0.value == "d3d11" && $0.data == "native"
        })
        XCTAssertTrue(epicWrites.contains {
            $0.key == DllOverridePolicy.globalDllOverridesKey && $0.value == "winevulkan" && $0.data == "builtin"
        })
        XCTAssertTrue(epicWrites.contains {
            $0.key == DllOverridePolicy.globalDllOverridesKey && $0.value == "vulkan-1" && $0.data == "builtin"
        })
        XCTAssertFalse(epicWrites.contains { $0.data == "d" && ($0.value == "winevulkan" || $0.value == "vulkan-1") })
        XCTAssertFalse(epicWrites.contains { $0.key.contains("EpicGamesLauncher.exe") })
        XCTAssertFalse(epicWrites.contains { $0.value == "renderer" })

        let steamWrites = DllOverridePolicy.registryWrites(
            engine: .grappleWine,
            backend: .dxmt,
            store: .steam
        ).compactMap(\.added)
        XCTAssertFalse(steamWrites.contains { $0.value == "winevulkan" })
        XCTAssertFalse(steamWrites.contains { $0.key.contains("EpicGamesLauncher.exe") })

        let gogWrites = DllOverridePolicy.registryWrites(
            engine: .grappleWine,
            backend: .wined3d,
            store: .gog
        ).compactMap(\.added)
        XCTAssertFalse(gogWrites.contains { $0.value == "winevulkan" })
        XCTAssertFalse(gogWrites.contains { $0.key.contains("EpicGamesLauncher.exe") })
        XCTAssertTrue(gogWrites.contains {
            $0.key == "HKCU\\Software\\Wine\\Direct3D" && $0.value == "renderer" && $0.data == "gdi"
        })
    }

    func testSteamWebHelperAlwaysBuiltin() {
        XCTAssertEqual(
            DllOverridePolicy.steamWebHelperOverrideString(),
            "d3d11,dxgi,d3d10core,winemetal=builtin"
        )
        let perApp = DllOverridePolicy.steamWebHelperOverrides()
        XCTAssertEqual(perApp["d3d11"], "builtin")
        XCTAssertEqual(perApp["dxgi"], "builtin")
        XCTAssertEqual(perApp["d3d10core"], "builtin")
        XCTAssertEqual(perApp["winemetal"], "builtin")

        let writes = DllOverridePolicy.registryWrites(
            engine: .grappleWine,
            backend: .dxmt,
            store: .steam
        ).compactMap(\.added)
        let webhelper = writes.filter { $0.key.contains("steamwebhelper.exe") }
        XCTAssertEqual(webhelper.count, 4)
        XCTAssertTrue(webhelper.allSatisfy { $0.data == "builtin" })
        XCTAssertTrue(webhelper.allSatisfy { $0.key.contains("AppDefaults\\steamwebhelper.exe") })
        XCTAssertFalse(DllOverridePolicy.steamWebHelperAppKey.contains("AppDefaultssteamwebhelper"))
        XCTAssertTrue(writes.contains { $0.value == "RetinaMode" && $0.data == "n" })
        XCTAssertFalse(writes.contains { $0.key == DllOverridePolicy.globalDllOverridesKey })
    }

    func testStagingRegistryNeverSetsNativeDXMT() {
        let writes = DllOverridePolicy.registryWrites(
            engine: .staging,
            backend: .dxmt,
            store: .steam
        ).compactMap(\.added)
        let globalD3D = writes.filter { $0.value == "d3d11" && !$0.key.contains("AppDefaults") }
        XCTAssertEqual(globalD3D.first?.data, "builtin")
    }

    func testMigrationFixesStagingNativeAndRetina() {
        let userReg = """
        [Software\\\\Wine\\\\DllOverrides] 123
        "d3d11"="native"
        "dxgi"="native"
        "winemetal"="native"

        [Software\\\\Wine\\\\Mac Driver] 456
        "RetinaMode"="y"
        """

        let writes = SteamBottleMigration.writes(
            userReg: userReg,
            engine: .staging,
            backend: .dxmt
        )
        XCTAssertTrue(SteamBottleMigration.needsFix(userReg: userReg, engine: .staging, backend: .dxmt))
        let added = writes.compactMap(\.added)
        XCTAssertTrue(added.contains { $0.value == "d3d11" && $0.data == "builtin" })
        XCTAssertTrue(added.contains { $0.value == "RetinaMode" && $0.data == "n" })
        XCTAssertTrue(added.contains { $0.key.contains("AppDefaults\\steamwebhelper.exe") && $0.value == "dxgi" && $0.data == "builtin" })
    }

    func testMigrationClearsGrappleGlobalOverridesAndBrokenAppDefaults() {
        let userReg = """
        [Software\\\\Wine\\\\DllOverrides] 123
        "d3d11"="native"
        "dxgi"="native"
        "d3d10core"="native"
        "winemetal"="native"

        [Software\\\\Wine\\\\AppDefaultssteamwebhelper.exe\\\\DllOverrides] 789
        "d3d11"="builtin"

        [Software\\\\Wine\\\\Mac Driver] 456
        "RetinaMode"="y"
        """

        XCTAssertTrue(WineUserRegParser.hasBrokenSteamWebHelperKey(userReg))
        let ops = SteamBottleMigration.writes(
            userReg: userReg,
            engine: .grappleWine,
            backend: .dxmt
        )
        XCTAssertTrue(ops.contains(.deleteKey(DllOverridePolicy.brokenSteamWebHelperKey)))
        XCTAssertTrue(ops.contains(.deleteValue(key: DllOverridePolicy.globalDllOverridesKey, value: "d3d11")))
        XCTAssertTrue(ops.contains(.deleteValue(key: DllOverridePolicy.globalDllOverridesKey, value: "winemetal")))
        let added = ops.compactMap(\.added)
        XCTAssertFalse(added.contains { $0.key == DllOverridePolicy.globalDllOverridesKey })
        XCTAssertTrue(added.contains { $0.value == "RetinaMode" && $0.data == "n" })
        XCTAssertTrue(added.contains { $0.key.contains("AppDefaults\\steamwebhelper.exe") && $0.data == "builtin" })
        XCTAssertFalse(added.contains { $0.key.contains("AppDefaultssteamwebhelper") })
    }

    func testBrokenAppDefaultsKeyMatchesGluedTypo() {
        XCTAssertEqual(
            DllOverridePolicy.brokenSteamWebHelperKey,
            "HKCU\\Software\\Wine\\AppDefaultssteamwebhelper.exe"
        )
        XCTAssertEqual(
            DllOverridePolicy.steamWebHelperAppKey,
            "HKCU\\Software\\Wine\\AppDefaults\\steamwebhelper.exe\\DllOverrides"
        )
        XCTAssertEqual(
            WineRegOp.deleteKey(DllOverridePolicy.brokenSteamWebHelperKey).argv,
            ["reg", "delete", DllOverridePolicy.brokenSteamWebHelperKey, "/f"]
        )
    }

    func testProcessArgumentLinesReadsBeforeWait() {
        // Invariant covered in ProcessPipeTests: drain stdout before waitUntilExit.
        let lines = PrefixRuntime.processArgumentLines()
        XCTAssertFalse(lines.isEmpty)
    }

    func testRunningStateRequiresSteamExeAndPrefix() {
        let prefix = "/bottles/steam/prefix"
        XCTAssertTrue(
            PrefixRuntime.isStoreProcessRunning(
                executableName: "steam.exe",
                prefixPath: prefix,
                processLines: [
                    "wine steam.exe -no-cef-sandbox WINEPREFIX=\(prefix) HOME=/Users/me"
                ]
            )
        )
        XCTAssertFalse(
            PrefixRuntime.isStoreProcessRunning(
                executableName: "steam.exe",
                prefixPath: prefix,
                processLines: [
                    "wineserver WINEPREFIX=\(prefix)",
                    "wine steam.exe WINEPREFIX=/bottles/other/prefix"
                ]
            )
        )
    }

    func testUserRegParser() {
        let contents = """
        [Software\\\\Wine\\\\DllOverrides] 1
        #time=1d
        "d3d11"="native"
        "dxgi"="builtin"

        [Software\\\\Wine\\\\Mac Driver] 2
        "RetinaMode"="n"
        """
        let overrides = WineUserRegParser.dllOverrides(in: contents)
        XCTAssertEqual(overrides["d3d11"], "native")
        XCTAssertEqual(overrides["dxgi"], "builtin")
        XCTAssertEqual(WineUserRegParser.retinaMode(in: contents), "n")
    }

    func testDXMTUnixLibCopyPlan() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cask-dxmt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let overlayRoot = root.appendingPathComponent("overlay")
        let engineRoot = root.appendingPathComponent("engine")
        try touch(overlayRoot.appendingPathComponent("x86_64-unix/winemetal.so"))
        try touch(overlayRoot.appendingPathComponent("x86_64-windows/d3d11.dll"))
        try touch(engineRoot.appendingPathComponent("bin/wine"))
        try touch(engineRoot.appendingPathComponent("bin/wineserver"))
        try FileManager.default.createDirectory(
            at: engineRoot.appendingPathComponent("lib/wine/x86_64-unix"),
            withIntermediateDirectories: true
        )

        let overlay = OverlayLayout.resolve(installRoot: overlayRoot)
        let engine = EngineLayout.resolve(installRoot: engineRoot)
        XCTAssertNotNil(overlay)
        XCTAssertNotNil(engine)
        XCTAssertTrue(DXMTUnixLib.needsInstall(overlay: overlay!, engine: engine!))
        try DXMTUnixLib.installIfNeeded(overlay: overlay!, engine: engine!)
        XCTAssertFalse(DXMTUnixLib.needsInstall(overlay: overlay!, engine: engine!))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: engine!.unix64Dir!.appendingPathComponent("winemetal.so").path)
        )

        let system32 = root.appendingPathComponent("system32")
        let syswow64 = root.appendingPathComponent("syswow64")
        let plan = DXMTWindowsDLLs.copyPlan(overlay: overlay!, system32: system32, syswow64: syswow64)
        XCTAssertTrue(plan.contains { $0.from.lastPathComponent == "d3d11.dll" && $0.to.path.contains("system32") })
    }

    func testDXMTWindowsDLLsReplaceEngineBuiltinsAndCopyWinemetalIntoPrefix() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cask-dxmt-win-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let overlayRoot = root.appendingPathComponent("overlay")
        let engineRoot = root.appendingPathComponent("engine")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/d3d11.dll"), "dxmt-d3d11")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/dxgi.dll"), "dxmt-dxgi")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/d3d10core.dll"), "dxmt-d3d10core")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/winemetal.dll"), "dxmt-winemetal")
        try write(overlayRoot.appendingPathComponent("i386-windows/d3d11.dll"), "dxmt-d3d11-32")
        try write(overlayRoot.appendingPathComponent("i386-windows/dxgi.dll"), "dxmt-dxgi-32")
        try write(overlayRoot.appendingPathComponent("i386-windows/d3d10core.dll"), "dxmt-d3d10core-32")
        try write(overlayRoot.appendingPathComponent("i386-windows/winemetal.dll"), "dxmt-winemetal-32")
        try touch(engineRoot.appendingPathComponent("bin/wine"))
        try touch(engineRoot.appendingPathComponent("bin/wineserver"))
        try write(engineRoot.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"), "wined3d-d3d11")
        try write(engineRoot.appendingPathComponent("lib/wine/x86_64-windows/dxgi.dll"), "wined3d-dxgi")
        try write(engineRoot.appendingPathComponent("lib/wine/i386-windows/d3d11.dll"), "wined3d-d3d11-32")

        let overlay = try XCTUnwrap(OverlayLayout.resolve(installRoot: overlayRoot))
        let engine = try XCTUnwrap(EngineLayout.resolve(installRoot: engineRoot))
        XCTAssertTrue(DXMTWindowsDLLs.needsInstall(overlay: overlay, engine: engine))
        XCTAssertTrue(DXMTWindowsDLLs.missingRequired(in: overlay).isEmpty)

        let enginePlan = DXMTWindowsDLLs.engineCopyPlan(overlay: overlay, engine: engine)
        XCTAssertTrue(enginePlan.contains {
            $0.from.lastPathComponent == "d3d11.dll" && $0.to.path.hasSuffix("lib/wine/x86_64-windows/d3d11.dll")
        })
        XCTAssertTrue(enginePlan.contains {
            $0.from.lastPathComponent == "winemetal.dll" && $0.to.path.hasSuffix("lib/wine/x86_64-windows/winemetal.dll")
        })
        XCTAssertTrue(enginePlan.contains {
            $0.to.path.hasSuffix("lib/wine/i386-windows/d3d11.dll")
        })

        try DXMTWindowsDLLs.installIntoEngine(overlay: overlay, engine: engine)
        XCTAssertFalse(DXMTWindowsDLLs.needsInstall(overlay: overlay, engine: engine))

        let win64 = try XCTUnwrap(engine.windows64Dir)
        XCTAssertEqual(try String(contentsOf: win64.appendingPathComponent("d3d11.dll"), encoding: .utf8), "dxmt-d3d11")
        XCTAssertEqual(try String(contentsOf: win64.appendingPathComponent("dxgi.dll"), encoding: .utf8), "dxmt-dxgi")
        XCTAssertEqual(try String(contentsOf: win64.appendingPathComponent("d3d10core.dll"), encoding: .utf8), "dxmt-d3d10core")
        XCTAssertEqual(try String(contentsOf: win64.appendingPathComponent("winemetal.dll"), encoding: .utf8), "dxmt-winemetal")
        let win32 = try XCTUnwrap(engine.windows32Dir)
        XCTAssertEqual(try String(contentsOf: win32.appendingPathComponent("d3d11.dll"), encoding: .utf8), "dxmt-d3d11-32")
        XCTAssertEqual(try String(contentsOf: win32.appendingPathComponent("winemetal.dll"), encoding: .utf8), "dxmt-winemetal-32")

        let system32 = root.appendingPathComponent("prefix/drive_c/windows/system32")
        let syswow64 = root.appendingPathComponent("prefix/drive_c/windows/syswow64")
        try DXMTWindowsDLLs.installIntoPrefix(overlay: overlay, system32: system32, syswow64: syswow64)
        XCTAssertEqual(try String(contentsOf: system32.appendingPathComponent("winemetal.dll"), encoding: .utf8), "dxmt-winemetal")
        XCTAssertEqual(try String(contentsOf: system32.appendingPathComponent("d3d11.dll"), encoding: .utf8), "dxmt-d3d11")
        XCTAssertEqual(try String(contentsOf: syswow64.appendingPathComponent("winemetal.dll"), encoding: .utf8), "dxmt-winemetal-32")
    }

    func testMissingWinemetalIsDetectedRatherThanSkipped() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cask-dxmt-missing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let overlayRoot = root.appendingPathComponent("overlay")
        let engineRoot = root.appendingPathComponent("engine")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/d3d11.dll"), "dxmt-d3d11")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/dxgi.dll"), "dxmt-dxgi")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/d3d10core.dll"), "dxmt-d3d10core")
        try touch(engineRoot.appendingPathComponent("bin/wine"))
        try touch(engineRoot.appendingPathComponent("bin/wineserver"))
        try write(engineRoot.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"), "wined3d-d3d11")

        let overlay = try XCTUnwrap(OverlayLayout.resolve(installRoot: overlayRoot))
        let engine = try XCTUnwrap(EngineLayout.resolve(installRoot: engineRoot))
        XCTAssertEqual(DXMTWindowsDLLs.missingRequired(in: overlay), ["winemetal.dll"])

        XCTAssertThrowsError(try DXMTWindowsDLLs.installIntoEngine(overlay: overlay, engine: engine)) { error in
            guard case EngineError.overlayFileMissing(let name, let file, let path) = error else {
                return XCTFail("expected overlayFileMissing, got \(error)")
            }
            XCTAssertEqual(name, "DXMT")
            XCTAssertEqual(file, "winemetal.dll")
            XCTAssertEqual(path, overlay.root.path)
        }
        XCTAssertEqual(
            try String(contentsOf: engine.windows64Dir!.appendingPathComponent("d3d11.dll"), encoding: .utf8),
            "wined3d-d3d11",
            "partial install must not replace builtins when winemetal is missing"
        )

        let system32 = root.appendingPathComponent("system32")
        let syswow64 = root.appendingPathComponent("syswow64")
        XCTAssertThrowsError(
            try DXMTWindowsDLLs.installIntoPrefix(overlay: overlay, system32: system32, syswow64: syswow64)
        ) { error in
            guard case EngineError.overlayFileMissing(_, let file, _) = error else {
                return XCTFail("expected overlayFileMissing, got \(error)")
            }
            XCTAssertEqual(file, "winemetal.dll")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: system32.appendingPathComponent("d3d11.dll").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: system32.appendingPathComponent("winemetal.dll").path))
    }

    func testWined3dBackendRestoresEngineBuiltinsAfterDXMTInstall() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cask-dxmt-restore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let overlayRoot = root.appendingPathComponent("overlay")
        let engineRoot = root.appendingPathComponent("engine")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/d3d11.dll"), "dxmt-d3d11")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/dxgi.dll"), "dxmt-dxgi")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/d3d10core.dll"), "dxmt-d3d10core")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/winemetal.dll"), "dxmt-winemetal")
        try touch(engineRoot.appendingPathComponent("bin/wine"))
        try touch(engineRoot.appendingPathComponent("bin/wineserver"))
        try write(engineRoot.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"), "wined3d-d3d11")
        try write(engineRoot.appendingPathComponent("lib/wine/x86_64-windows/dxgi.dll"), "wined3d-dxgi")
        try write(engineRoot.appendingPathComponent("lib/wine/x86_64-windows/d3d10core.dll"), "wined3d-d3d10core")

        let overlay = try XCTUnwrap(OverlayLayout.resolve(installRoot: overlayRoot))
        let engine = try XCTUnwrap(EngineLayout.resolve(installRoot: engineRoot))
        let win64 = try XCTUnwrap(engine.windows64Dir)

        func assertEngineMatchesBuiltins(cycle: String) throws {
            XCTAssertEqual(
                try String(contentsOf: win64.appendingPathComponent("d3d11.dll"), encoding: .utf8),
                "wined3d-d3d11",
                "\(cycle): d3d11 must be the Wine builtin"
            )
            XCTAssertNotEqual(
                try String(contentsOf: win64.appendingPathComponent("d3d11.dll"), encoding: .utf8),
                "dxmt-d3d11",
                "\(cycle): d3d11 must not be the DXMT PE"
            )
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: win64.appendingPathComponent("winemetal.dll").path),
                "\(cycle): winemetal.dll must not remain in the engine tree"
            )
            for name in DXMTWindowsDLLs.names {
                let sidecar = win64.appendingPathComponent(name)
                    .appendingPathExtension(DXMTWindowsDLLs.backupExtension)
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: sidecar.path),
                    "\(cycle): leftover \(sidecar.lastPathComponent)"
                )
            }
        }

        try DXMTWindowsDLLs.installIntoEngine(overlay: overlay, engine: engine)
        XCTAssertEqual(try String(contentsOf: win64.appendingPathComponent("d3d11.dll"), encoding: .utf8), "dxmt-d3d11")
        try DXMTWindowsDLLs.syncEngine(overlay: overlay, engine: engine, backend: .wined3d)
        try assertEngineMatchesBuiltins(cycle: "first")

        // Second DXMT apply, then another apply while already overlaid (EngineManager + launch).
        try DXMTWindowsDLLs.installIntoEngine(overlay: overlay, engine: engine)
        XCTAssertFalse(DXMTWindowsDLLs.needsInstall(overlay: overlay, engine: engine))
        try DXMTWindowsDLLs.installIntoEngine(overlay: overlay, engine: engine)
        try DXMTWindowsDLLs.syncEngine(overlay: overlay, engine: engine, backend: .wined3d)
        try assertEngineMatchesBuiltins(cycle: "second")
    }

    func testD3DMetalBackendRestoresEngineBuiltinsAfterDXMTInstall() throws {
        for backend in GraphicsBackend.allCases where backend != .dxmt {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("cask-dxmt-\(backend.shortLabel)-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }

            let overlayRoot = root.appendingPathComponent("overlay")
            let engineRoot = root.appendingPathComponent("engine")
            try write(overlayRoot.appendingPathComponent("x86_64-windows/d3d11.dll"), "dxmt-d3d11")
            try write(overlayRoot.appendingPathComponent("x86_64-windows/dxgi.dll"), "dxmt-dxgi")
            try write(overlayRoot.appendingPathComponent("x86_64-windows/d3d10core.dll"), "dxmt-d3d10core")
            try write(overlayRoot.appendingPathComponent("x86_64-windows/winemetal.dll"), "dxmt-winemetal")
            try touch(engineRoot.appendingPathComponent("bin/wine"))
            try touch(engineRoot.appendingPathComponent("bin/wineserver"))
            try write(engineRoot.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"), "wined3d-d3d11")
            try write(engineRoot.appendingPathComponent("lib/wine/x86_64-windows/dxgi.dll"), "wined3d-dxgi")
            try write(engineRoot.appendingPathComponent("lib/wine/x86_64-windows/d3d10core.dll"), "wined3d-d3d10core")

            let overlay = try XCTUnwrap(OverlayLayout.resolve(installRoot: overlayRoot))
            let engine = try XCTUnwrap(EngineLayout.resolve(installRoot: engineRoot))
            try DXMTWindowsDLLs.installIntoEngine(overlay: overlay, engine: engine)
            XCTAssertEqual(
                try String(contentsOf: engine.windows64Dir!.appendingPathComponent("d3d11.dll"), encoding: .utf8),
                "dxmt-d3d11"
            )

            try DXMTWindowsDLLs.syncEngine(overlay: overlay, engine: engine, backend: backend)
            XCTAssertEqual(
                try String(contentsOf: engine.windows64Dir!.appendingPathComponent("d3d11.dll"), encoding: .utf8),
                "wined3d-d3d11",
                "\(backend.shortLabel) must restore the Wine builtin"
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: engine.windows64Dir!.appendingPathComponent("winemetal.dll").path
                ),
                "\(backend.shortLabel) must not leave winemetal.dll in the engine tree"
            )
        }
    }

    func testIncompleteOverlayWithoutD3D11DoesNotReplaceAnyEngineFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cask-dxmt-partial-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let overlayRoot = root.appendingPathComponent("overlay")
        let engineRoot = root.appendingPathComponent("engine")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/dxgi.dll"), "dxmt-dxgi")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/d3d10core.dll"), "dxmt-d3d10core")
        try write(overlayRoot.appendingPathComponent("x86_64-windows/winemetal.dll"), "dxmt-winemetal")
        try touch(engineRoot.appendingPathComponent("bin/wine"))
        try touch(engineRoot.appendingPathComponent("bin/wineserver"))
        try write(engineRoot.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"), "wined3d-d3d11")
        try write(engineRoot.appendingPathComponent("lib/wine/x86_64-windows/dxgi.dll"), "wined3d-dxgi")

        let overlay = try XCTUnwrap(OverlayLayout.resolve(installRoot: overlayRoot))
        let engine = try XCTUnwrap(EngineLayout.resolve(installRoot: engineRoot))
        XCTAssertTrue(DXMTWindowsDLLs.missingRequired(in: overlay).contains("d3d11.dll"))

        XCTAssertThrowsError(try DXMTWindowsDLLs.installIntoEngine(overlay: overlay, engine: engine)) { error in
            guard case EngineError.overlayFileMissing(let name, let file, _) = error else {
                return XCTFail("expected overlayFileMissing, got \(error)")
            }
            XCTAssertEqual(name, "DXMT")
            XCTAssertEqual(file, "d3d11.dll")
        }
        XCTAssertEqual(
            try String(contentsOf: engine.windows64Dir!.appendingPathComponent("d3d11.dll"), encoding: .utf8),
            "wined3d-d3d11"
        )
        XCTAssertEqual(
            try String(contentsOf: engine.windows64Dir!.appendingPathComponent("dxgi.dll"), encoding: .utf8),
            "wined3d-dxgi"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: engine.windows64Dir!.appendingPathComponent("winemetal.dll").path
            )
        )
    }

    func testWineManagerWiresDXMTPlacementOnLaunchAndWinecfg() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CaskLauncherCore/WineManager.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let bodies = swiftFunctionBodies(in: source)
        let callers = [
            "configurePrefix",
            "launchStore",
            "configureCustomPrefix",
            "launchInCustomBottle",
            "configureLauncherBottle",
            "openWinecfg",
            "launchExecutable"
        ]
        for name in callers {
            let body = try XCTUnwrap(bodies[name], "missing \(name) in WineManager.swift")
            XCTAssertTrue(
                body.contains("ensureDXMTPlacement"),
                "\(name) must call ensureDXMTPlacement"
            )
        }
        let placement = try XCTUnwrap(bodies["ensureDXMTPlacement"])
        XCTAssertTrue(placement.contains("syncEngine"), "ensureDXMTPlacement must sync the engine tree")
        XCTAssertTrue(
            placement.contains("graphicsBackend"),
            "ensureDXMTPlacement must pass the bottle backend into syncEngine"
        )
    }

    func testRegWriteArgv() {
        let write = WineRegWrite(
            key: #"HKCU\Software\Wine\Mac Driver"#,
            value: "RetinaMode",
            data: "n"
        )
        XCTAssertEqual(
            write.argv,
            ["reg", "add", #"HKCU\Software\Wine\Mac Driver"#, "/v", "RetinaMode", "/t", "REG_SZ", "/d", "n", "/f"]
        )
    }

    private func swiftFunctionBodies(in source: String) -> [String: String] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [String: String] = [:]
        var index = 0
        while index < lines.count {
            guard let name = wineManagerFunctionName(from: lines[index]) else {
                index += 1
                continue
            }
            var depth = 0
            var started = false
            var body: [String] = []
            var cursor = index
            while cursor < lines.count {
                let line = lines[cursor]
                for character in line {
                    if character == "{" {
                        depth += 1
                        started = true
                    } else if character == "}" {
                        depth -= 1
                    }
                }
                if started {
                    body.append(line)
                }
                if started && depth == 0 {
                    result[name] = body.joined(separator: "\n")
                    break
                }
                cursor += 1
            }
            index = cursor + 1
        }
        return result
    }

    private func wineManagerFunctionName(from line: String) -> String? {
        guard line.hasPrefix("    "), !line.hasPrefix("        ") else { return nil }
        let rest = String(line.dropFirst(4))
        for prefix in ["public func ", "private func ", "internal func ", "func "] {
            guard rest.hasPrefix(prefix) else { continue }
            let name = rest.dropFirst(prefix.count).prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
            return name.isEmpty ? nil : String(name)
        }
        return nil
    }

    private func touch(_ url: URL) throws {
        try write(url, "x")
    }

    private func write(_ url: URL, _ contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    func testSteamFirstRunUpdateUsesPlainArgumentsButKeepsSyncFix() {
        let wineLib = URL(fileURLWithPath: "/engines/grapple-wine/grapple-wine/lib/wine")
        let steam = URL(fileURLWithPath: "/bottles/steam/prefix/drive_c/Program Files (x86)/Steam/steam.exe")
        let first = StoreLaunchRecipe.build(store: .steam, executable: steam, wineLibDir: wineLib, firstRunUpdate: true)
        XCTAssertEqual(first.arguments, ["steam.exe"])
        let normal = StoreLaunchRecipe.build(store: .steam, executable: steam, wineLibDir: wineLib)
        XCTAssertEqual(first.environment, normal.environment)
        XCTAssertTrue(normal.arguments.contains("-noverifyfiles"))
    }
}
