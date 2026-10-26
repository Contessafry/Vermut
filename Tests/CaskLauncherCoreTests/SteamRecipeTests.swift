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

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: url)
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
