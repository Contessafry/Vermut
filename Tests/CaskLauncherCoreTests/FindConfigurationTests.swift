import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import CaskLauncherCore

final class FindConfigurationPlannerTests: XCTestCase {
    private func steamContext(
        engines: Set<WineEngine> = [.grappleWine, .staging],
        d3dMetal: Bool = false,
        compat: GameCompatibility? = nil
    ) -> FindConfigurationContext {
        FindConfigurationContext(
            store: .steam,
            installedEngines: engines,
            d3dMetalInstalled: d3dMetal,
            compatibility: compat
        )
    }

    func testPrunesDXVKOnVermutWineAndMissingStaging() {
        let onlyVermut = steamContext(engines: [.grappleWine])
        let dxvkVermut = FindConfigurationCombo(engine: .grappleWine, graphics: .dxvk)
        XCTAssertEqual(
            FindConfigurationPlanner.skipReason(for: dxvkVermut, context: onlyVermut),
            .dxvkRequiresStaging
        )
        XCTAssertFalse(FindConfigurationPlanner.plan(context: onlyVermut).contains { $0.graphics == .dxvk })

        let withStaging = steamContext(engines: [.grappleWine, .staging])
        XCTAssertNil(
            FindConfigurationPlanner.skipReason(
                for: FindConfigurationCombo(engine: .staging, graphics: .dxvk),
                context: withStaging
            )
        )
        XCTAssertTrue(FindConfigurationPlanner.plan(context: withStaging).contains {
            $0.engine == .staging && $0.graphics == .dxvk
        })
    }

    func testPrunesD3DMetalUnlessInstalled() {
        let missing = steamContext(d3dMetal: false)
        XCTAssertEqual(
            FindConfigurationPlanner.skipReason(
                for: FindConfigurationCombo(engine: .grappleWine, graphics: .d3dmetal),
                context: missing
            ),
            .d3dMetalMissing
        )
        XCTAssertFalse(FindConfigurationPlanner.plan(context: missing).contains { $0.graphics == .d3dmetal })

        let present = steamContext(d3dMetal: true)
        XCTAssertNil(
            FindConfigurationPlanner.skipReason(
                for: FindConfigurationCombo(engine: .grappleWine, graphics: .d3dmetal),
                context: present
            )
        )
    }

    func testPrunesDXMTOnStaging() {
        let context = steamContext()
        XCTAssertEqual(
            FindConfigurationPlanner.skipReason(
                for: FindConfigurationCombo(engine: .staging, graphics: .dxmt),
                context: context
            ),
            .dxmtUnsupportedByEngine
        )
    }

    func testPrunesKnownNotWorkingEngineGraphicsPair() {
        let compat = GameCompatibility(
            store: "steam",
            gameId: "1245620",
            gameName: "ELDEN RING",
            byGraphics: [
                "dxmt": .init(perfect: 0, issues: 0, broken: 3)
            ],
            recommended: "dxmt",
            totalReports: 3,
            knownNotWorking: [
                KnownNotWorkingCombo(graphics: "dxmt", engine: "vermut-wine")
            ]
        )
        let context = steamContext(compat: compat)
        XCTAssertTrue(
            FindConfigurationPlanner.matchesKnownNotWorking(
                FindConfigurationCombo(engine: .grappleWine, graphics: .dxmt),
                context: context
            )
        )
        XCTAssertEqual(
            FindConfigurationPlanner.skipReason(
                for: FindConfigurationCombo(engine: .grappleWine, graphics: .dxmt),
                context: context
            ),
            .knownNotWorking
        )
        XCTAssertFalse(FindConfigurationPlanner.plan(context: context).contains {
            $0.engine == .grappleWine && $0.graphics == .dxmt
        })
    }

    func testKnownNotWorkingGraphicsOnlySkipsEveryEngine() {
        let compat = GameCompatibility(
            store: "steam",
            gameId: "1",
            gameName: "Kingsway",
            byGraphics: ["dxmt": .init(perfect: 0, issues: 0, broken: 2)],
            recommended: nil,
            totalReports: 2,
            knownNotWorking: [KnownNotWorkingCombo(graphics: "dxmt", engine: nil)]
        )
        let context = steamContext(compat: compat)
        XCTAssertTrue(FindConfigurationPlanner.plan(context: context).allSatisfy { $0.graphics != .dxmt })
    }

    func testGOGLocksWineD3DAndOmitsOverlay() {
        let context = FindConfigurationContext(
            store: .gog,
            installedEngines: [.staging],
            d3dMetalInstalled: true
        )
        let plan = FindConfigurationPlanner.plan(context: context)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.allSatisfy { $0.graphics == .wined3d })
        XCTAssertTrue(plan.allSatisfy { $0.steamOverlayEnabled == false })
        XCTAssertEqual(
            FindConfigurationPlanner.skipReason(
                for: FindConfigurationCombo(engine: .staging, graphics: .dxmt),
                context: context
            ),
            .storeGraphicsLocked
        )
    }

    func testUninstalledEngineIsSkipped() {
        let context = steamContext(engines: [.grappleWine])
        XCTAssertEqual(
            FindConfigurationPlanner.skipReason(
                for: FindConfigurationCombo(engine: .devel, graphics: .wined3d),
                context: context
            ),
            .engineNotInstalled
        )
    }

    func testOrdersCompatRecommendationThenCommonDefault() {
        let compat = GameCompatibility(
            store: "steam",
            gameId: "620",
            gameName: "Portal 2",
            byGraphics: [
                "dxmt": .init(perfect: 0, issues: 0, broken: 1),
                "dxvk": .init(perfect: 2, issues: 1, broken: 0)
            ],
            recommended: "dxvk",
            totalReports: 4
        )
        let context = steamContext(compat: compat)
        let plan = FindConfigurationPlanner.plan(context: context)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertEqual(plan.first?.graphics, .dxvk)
        XCTAssertEqual(plan.first?.engine, .staging)
        XCTAssertFalse(plan.first?.steamOverlayEnabled ?? true)
        XCTAssertEqual(plan.first?.launchOption, .none)

        let defaultIndex = plan.firstIndex {
            $0.engine == .grappleWine && $0.graphics == .dxmt && !$0.steamOverlayEnabled && $0.launchOption == .none
        }
        let overlayOnIndex = plan.firstIndex {
            $0.engine == .grappleWine && $0.graphics == .dxmt && $0.steamOverlayEnabled && $0.launchOption == .none
        }
        if let defaultIndex, let overlayOnIndex {
            XCTAssertLessThan(defaultIndex, overlayOnIndex)
        }
    }

    func testLaunchOptionsNoneComesBeforeFlags() {
        let context = steamContext(engines: [.grappleWine])
        let plan = FindConfigurationPlanner.plan(context: context)
        let dxmt = plan.filter { $0.engine == .grappleWine && $0.graphics == .dxmt && !$0.steamOverlayEnabled }
        XCTAssertEqual(dxmt.first?.launchOption, .none)
        XCTAssertTrue(dxmt.contains { $0.launchOption == .forceGLCore })
        XCTAssertTrue(dxmt.contains { $0.launchOption == .unityD3D11NoSingleThreaded })
        if let none = dxmt.firstIndex(where: { $0.launchOption == .none }),
           let gl = dxmt.firstIndex(where: { $0.launchOption == .forceGLCore }) {
            XCTAssertLessThan(none, gl)
        }
    }

    func testComboPersistsIntoGameConfiguration() {
        let combo = FindConfigurationCombo(
            engine: .staging,
            graphics: .dxvk,
            steamOverlayEnabled: true,
            launchOption: .forceGLCore
        )
        let config = combo.gameConfiguration()
        XCTAssertEqual(config.engine, WineEngine.staging.rawValue)
        XCTAssertEqual(config.graphicsBackend, GraphicsBackend.dxvk.rawValue)
        XCTAssertTrue(config.steamOverlayEnabled)
        XCTAssertEqual(config.launchOptions, "-force-glcore")
        XCTAssertTrue(config.hasOverrides)
    }
}

final class FindConfigurationSuccessTests: XCTestCase {
    func testFatalMarkerFailsEvenIfProcessAndWindowLookFine() {
        let observation = FindConfigurationObservation(
            processAlive: true,
            aliveSeconds: 60,
            hasRealWindow: true,
            logText: "UnityPlayer: InitializeEngineGraphics failed\n"
        )
        let verdict = FindConfigurationSuccess.evaluate(observation, threshold: 45)
        if case .failed(let reason) = verdict {
            XCTAssertTrue(reason.contains("InitializeEngineGraphics failed"))
        } else {
            XCTFail("expected failed, got \(verdict)")
        }
    }

    func testUnityFailedToInitializePlayerIsFatal() {
        XCTAssertEqual(
            FindConfigurationSuccess.firstFatalMarker(in: "Failed to initialize player"),
            "Failed to initialize player"
        )
        XCTAssertTrue(FindConfigurationSuccess.containsFatalMarker("err: Failed to initialize the player (D3D11)"))
    }

    func testEarlyExitIsFailure() {
        let observation = FindConfigurationObservation(
            processAlive: false,
            aliveSeconds: 8,
            hasRealWindow: false,
            logText: ""
        )
        if case .failed(let reason) = FindConfigurationSuccess.evaluate(observation, threshold: 45) {
            XCTAssertTrue(reason.contains("exited"))
        } else {
            XCTFail("expected early-exit failure")
        }
    }

    func testCandidateRequiresAliveWindowAndThreshold() {
        let waiting = FindConfigurationObservation(
            processAlive: true,
            aliveSeconds: 20,
            hasRealWindow: true,
            logText: ""
        )
        XCTAssertEqual(FindConfigurationSuccess.evaluate(waiting, threshold: 45), .keepWaiting)

        let noWindow = FindConfigurationObservation(
            processAlive: true,
            aliveSeconds: 50,
            hasRealWindow: false,
            logText: ""
        )
        XCTAssertEqual(FindConfigurationSuccess.evaluate(noWindow, threshold: 45), .keepWaiting)

        let ready = FindConfigurationObservation(
            processAlive: true,
            aliveSeconds: 45,
            hasRealWindow: true,
            logText: "fixme:d3d: something noisy but not fatal"
        )
        XCTAssertEqual(FindConfigurationSuccess.evaluate(ready, threshold: 45), .candidate)
    }

    func testThresholdIsClampedToThirtySixty() {
        XCTAssertEqual(FindConfigurationSettings.clampThreshold(5), 30)
        XCTAssertEqual(FindConfigurationSettings.clampThreshold(90), 60)
        XCTAssertEqual(FindConfigurationSettings.clampThreshold(45), 45)
    }
}

final class FindGameProcessTests: XCTestCase {
    func testClassifiesGameVsSteamVsWineserver() {
        let prefix = "/Users/me/Library/Application Support/Vermut/bottles/steam/prefix"
        let lines = [
            "101  \(prefix)/../../../engines/staging/bin/wineserver -f",
            "202  C:\\Program Files (x86)\\Steam\\steam.exe -applaunch 620",
            "303  C:\\Program Files (x86)\\Steam\\bin\\steamwebhelper.exe",
            "404  C:\\Program Files (x86)\\Steam\\steamapps\\common\\Portal 2\\portal2.exe -game portal2",
            "505  /Applications/Steam.app/Contents/MacOS/steam_osx"
        ]
        let snap = FindGameProcess.classify(
            processLines: lines,
            prefixPath: prefix,
            installDir: "Portal 2",
            appId: "620"
        )
        XCTAssertEqual(snap.gamePIDs, [404])
        XCTAssertTrue(snap.steamClientPIDs.contains(202))
        XCTAssertTrue(snap.steamClientPIDs.contains(303))
        XCTAssertEqual(snap.wineserverPIDs, [101])
        XCTAssertFalse(snap.steamClientPIDs.contains(505), "native Steam must never be classified")
        XCTAssertTrue(snap.isGameAlive)
    }

    func testDoesNotTreatSteamClientAsGameEvenWhenAppIdAppears() {
        XCTAssertFalse(
            FindGameProcess.isGameCommand(
                "steam.exe -no-cef-sandbox -applaunch 620",
                installDir: "Portal 2",
                appId: "620",
                prefixPath: "/prefix"
            )
        )
        XCTAssertTrue(FindGameProcess.isSteamClient("steam.exe -applaunch 620"))
        XCTAssertTrue(FindGameProcess.isHostKeep("/engines/staging/bin/wineserver -f"))
    }

    func testStopSignalsOnlyGivenPIDs() {
        var signals: [(pid_t, Int32)] = []
        let stopped = FindGameProcess.stop(
            pids: [404, 404, 1],
            termGraceSeconds: 0,
            killGraceSeconds: 0,
            sleeper: { _ in },
            signalSender: { pid, sig in
                signals.append((pid, sig))
                return 0
            }
        )
        XCTAssertEqual(stopped, [404])
        XCTAssertEqual(signals.map(\.0), [404, 404])
        XCTAssertEqual(signals.map(\.1), [SIGTERM, SIGKILL])
    }

    func testNeedsStoreRestartOnlyWhenRuntimeProfileChanges() {
        let a = FindConfigurationCombo(engine: .grappleWine, graphics: .dxmt, launchOption: .none)
        let b = FindConfigurationCombo(engine: .grappleWine, graphics: .dxmt, launchOption: .forceGLCore)
        let c = FindConfigurationCombo(engine: .staging, graphics: .dxvk)
        XCTAssertFalse(FindGameProcess.needsStoreRestart(current: a, next: b))
        XCTAssertTrue(FindGameProcess.needsStoreRestart(current: a, next: c))
        XCTAssertTrue(FindGameProcess.needsStoreRestart(current: nil, next: a))
    }
}

final class FindConfigurationLogTests: XCTestCase {
    func testAttemptLogIsCappedAndRotated() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-find-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("attempt-01.log")
        let writer = CappedLogWriter(url: url, maxBytes: 2_048)
        for i in 0..<4_000 {
            writer.append(line: "wine err loop line \(i) that would have grown without a cap")
        }
        writer.flush()
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.uint64Value ?? 0
        XCTAssertLessThanOrEqual(size, 2_048)
        let rotated = CappedLogWriter.rotatedURL(for: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotated.path))
    }

    func testSummarizeTriedListsCombos() {
        let attempts = [
            FindConfigurationAttempt(
                index: 1,
                combo: FindConfigurationCombo(engine: .grappleWine, graphics: .dxmt),
                outcome: .failed,
                detail: "Fatal log marker: Failed to initialize player"
            ),
            FindConfigurationAttempt(
                index: 2,
                combo: FindConfigurationCombo(engine: .staging, graphics: .dxvk),
                outcome: .confirmed
            )
        ]
        let text = FindConfigurationLog.summarizeTried(attempts)
        XCTAssertTrue(text.contains("Vermut Wine · DXMT"))
        XCTAssertTrue(text.contains("failed"))
        XCTAssertTrue(text.contains("Wine Staging · DXVK"))
    }

    func testDirectoryUsesSanitizedAppId() {
        let url = FindConfigurationLog.directoryURL(store: .steam, appId: "Foo/Bar")
        XCTAssertTrue(url.path.contains("find-config"))
        XCTAssertTrue(url.path.hasSuffix("Foo_Bar"))
    }
}

final class FindLaunchOptionAndSteamArgsTests: XCTestCase {
    func testApplaunchAppendsExtraOptionsAfterAppId() {
        let args = SteamGameLaunch.applaunchArguments(
            appId: "620",
            extraLaunchOptions: ["-force-glcore"]
        )
        XCTAssertEqual(args.suffix(3).map { $0 }, ["-applaunch", "620", "-force-glcore"])
        XCTAssertEqual(
            SteamGameLaunch.rungameURI(appId: "620", extraLaunchOptions: ["-force-glcore"]),
            "steam://rungameid/620//-force-glcore"
        )
    }

    func testRecipeForwardsLaunchOptions() {
        let wineLib = URL(fileURLWithPath: "/engines/grapple-wine/lib/wine")
        let steam = URL(fileURLWithPath: "/bottles/steam/prefix/drive_c/Program Files (x86)/Steam/steam.exe")
        let recipe = StoreLaunchRecipe.build(
            store: .steam,
            executable: steam,
            wineLibDir: wineLib,
            steamAppId: "620",
            extraLaunchOptions: ["-force-d3d11-no-singlethreaded"]
        )
        XCTAssertEqual(recipe.arguments.last, "-force-d3d11-no-singlethreaded")
        XCTAssertTrue(recipe.arguments.contains("-applaunch"))
    }

    func testLegendaryForwardsGameArgsAfterDashDash() {
        let args = LegendaryCLI.launchArguments(
            appName: "Celeste",
            wine: "/opt/wine/bin/wine64",
            prefix: "/prefix",
            extraGameArguments: ["-force-glcore"]
        )
        XCTAssertEqual(
            args,
            ["launch", "Celeste", "--wine", "/opt/wine/bin/wine64", "--wine-prefix", "/prefix", "--", "-force-glcore"]
        )
    }

    func testGameConfigurationLaunchOptionsRoundTrip() throws {
        let json = Data(#"{}"#.utf8)
        let empty = try JSONDecoder().decode(GameConfiguration.self, from: json)
        XCTAssertEqual(empty.launchOptions, "")
        XCTAssertFalse(empty.hasOverrides)

        var config = GameConfiguration(launchOptions: "-force-glcore")
        XCTAssertTrue(config.hasOverrides)
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(GameConfiguration.self, from: encoded)
        XCTAssertEqual(decoded.launchOptions, "-force-glcore")
        config.resetAll()
        XCTAssertEqual(config.launchOptions, "")
        XCTAssertFalse(config.hasOverrides)
    }

    func testResolverPassesLaunchOptions() {
        let resolved = GameSettingsResolver.resolve(
            game: GameConfiguration(launchOptions: "-force-glcore"),
            bottle: BottleConfiguration(),
            global: AppConfiguration(),
            store: .steam
        )
        XCTAssertEqual(resolved.launchOptions, ["-force-glcore"])
    }

    func testFromStoredMapsKnownPresets() {
        XCTAssertEqual(FindLaunchOption.fromStored(""), .none)
        XCTAssertEqual(FindLaunchOption.fromStored("-force-glcore"), .forceGLCore)
        XCTAssertEqual(FindLaunchOption.fromStored("  -force-d3d11-no-singlethreaded ").id, FindLaunchOption.unityD3D11NoSingleThreaded.id)
    }
}
