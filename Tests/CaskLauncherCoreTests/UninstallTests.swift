import XCTest
@testable import CaskLauncherCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class UninstallPathPolicyTests: XCTestCase {
    func testHardExclusionsCoverNativeStoresAndHomebrew() {
        let home = URL(fileURLWithPath: "/tmp/vermut-uninstall-home-\(UUID().uuidString)", isDirectory: true)
        let exclusions = UninstallPathPolicy.hardExclusionRoots(home: home)
        let paths = exclusions.map(\.path)
        XCTAssertTrue(paths.contains { $0.hasSuffix("/Application Support/Steam") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/Application Support/GOG.com") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/Application Support/Epic") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/Application Support/CrossOver") })
        XCTAssertTrue(paths.contains("/opt/homebrew"))
        XCTAssertTrue(paths.contains("/Applications/Steam.app"))
    }

    func testWhitelistAllowsVermutAppSupport() {
        let home = URL(fileURLWithPath: "/tmp/vermut-home-\(UUID().uuidString)", isDirectory: true)
        let appSupport = home.appendingPathComponent(
            "Library/Application Support/Vermut",
            isDirectory: true
        )
        let allowed = UninstallPathPolicy.allowedPrefixes(
            appSupport: appSupport,
            appBundle: nil,
            home: home
        )
        XCTAssertTrue(
            UninstallPathPolicy.isWithinWhitelist(
                appSupport.appendingPathComponent("engines"),
                allowedPrefixes: allowed
            )
        )
        XCTAssertFalse(
            UninstallPathPolicy.isWithinWhitelist(
                home.appendingPathComponent("Library/Application Support/Steam"),
                allowedPrefixes: allowed
            )
        )
    }

    func testNativeSteamIsHardExcluded() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let steam = home.appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
        XCTAssertTrue(UninstallPathPolicy.isHardExcluded(steam, home: home))
        XCTAssertFalse(
            UninstallPathPolicy.isHardExcluded(
                home.appendingPathComponent("Library/Application Support/Vermut/bottles/steam"),
                home: home
            )
        )
    }

    func testWineZDriveSymlinkDetection() {
        let z = URL(fileURLWithPath: "/tmp/prefix/dosdevices/z:", isDirectory: false)
        XCTAssertTrue(UninstallPathPolicy.isWineZDriveSymlink(z))
        XCTAssertFalse(UninstallPathPolicy.shouldDescend(into: z))
        let other = URL(fileURLWithPath: "/tmp/prefix/drive_c/game.exe")
        XCTAssertFalse(UninstallPathPolicy.isWineZDriveSymlink(other))
    }

    func testValidateSkipsPathsOutsideWhitelist() {
        let home = URL(fileURLWithPath: "/tmp/vermut-wl-\(UUID().uuidString)", isDirectory: true)
        let appSupport = home.appendingPathComponent(
            "Library/Application Support/Vermut",
            isDirectory: true
        )
        let allowed = UninstallPathPolicy.allowedPrefixes(
            appSupport: appSupport,
            appBundle: nil,
            home: home
        )
        let outside = URL(fileURLWithPath: "/etc/passwd")
        let reason = UninstallPathPolicy.validateForRemoval(
            outside,
            allowedPrefixes: allowed,
            home: home
        )
        XCTAssertEqual(reason, "Skipped for safety: path is outside Vermut's folder.")
    }

    func testZDriveSymlinkPassesValidationAsLinkNotTarget() {
        let home = URL(fileURLWithPath: "/tmp/vermut-z-\(UUID().uuidString)", isDirectory: true)
        let appSupport = home.appendingPathComponent(
            "Library/Application Support/Vermut",
            isDirectory: true
        )
        let z = appSupport.appendingPathComponent("bottles/steam/prefix/dosdevices/z:")
        let allowed = UninstallPathPolicy.allowedPrefixes(
            appSupport: appSupport,
            appBundle: nil,
            home: home
        )
        XCTAssertNil(
            UninstallPathPolicy.validateForRemoval(z, allowedPrefixes: allowed, home: home)
        )
        XCTAssertEqual(UninstallPathPolicy.pathForSafetyCheck(z).path, z.standardizedFileURL.path)
    }
}

final class UninstallSizeCalculatorTests: XCTestCase {
    func testSizeSkipsWineZDriveSymlinkTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-size-\(UUID().uuidString)", isDirectory: true)
        let dos = root.appendingPathComponent("prefix/dosdevices", isDirectory: true)
        try FileManager.default.createDirectory(at: dos, withIntermediateDirectories: true)
        let realFile = root.appendingPathComponent("prefix/drive_c/game.bin")
        try FileManager.default.createDirectory(
            at: realFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = Data(repeating: 0xAB, count: 4096)
        try payload.write(to: realFile)

        let z = dos.appendingPathComponent("z:")
        try FileManager.default.createSymbolicLink(
            atPath: z.path,
            withDestinationPath: "/"
        )

        let bytes = UninstallSizeCalculator.byteCount(of: root)
        XCTAssertEqual(bytes, Int64(payload.count))
        XCTAssertLessThan(bytes, 1_000_000)
        try? FileManager.default.removeItem(at: root)
    }

    func testFormattedByteCountUsesFileStyle() {
        let text = UninstallSizeCalculator.formattedByteCount(1_500_000_000)
        XCTAssertFalse(text.isEmpty)
    }
}

final class UninstallPlanDefaultsTests: XCTestCase {
    func testDefaultSelectionExcludesBottlesAndHasNoAppTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-plan-\(UUID().uuidString)", isDirectory: true)
        let bottles = root.appendingPathComponent("bottles", isDirectory: true)
        let engines = root.appendingPathComponent("engines", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: bottles, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: engines, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: bottles.appendingPathComponent("steam", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: engines.appendingPathComponent("grapple-wine", isDirectory: true),
            withIntermediateDirectories: true
        )

        let plan = UninstallPlanBuilder.makeDefaultPlan(
            context: UninstallPlanBuilder.Context(
                appSupportURL: root,
                bottlesURL: bottles,
                enginesURL: engines,
                cacheURL: cache,
                configURL: root.appendingPathComponent("config.json"),
                customBottles: [],
                gameCountByStore: [.steam: 3],
                home: root,
                fileManager: .default
            )
        )

        XCTAssertTrue(plan.engines.isSelected)
        XCTAssertTrue(plan.caches.isSelected)
        XCTAssertTrue(plan.logs.isSelected)
        XCTAssertTrue(plan.preferences.isSelected)
        XCTAssertFalse(plan.bottles.isEmpty)
        XCTAssertTrue(plan.bottles.allSatisfy { !$0.isSelected })
        XCTAssertFalse(plan.bottlesExpanded)
        XCTAssertEqual(plan.bottlesTriState, .off)
        XCTAssertEqual(plan.bottles.first?.detail, "3 games installed")
        XCTAssertFalse(plan.allTargets.contains { $0.displayName == "Vermut app" })
        XCTAssertFalse(UninstallCategory.allCases.map(\.rawValue).contains("app"))

        try? FileManager.default.removeItem(at: root)
    }

    func testSelectAllAndDeselectAll() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-sel-\(UUID().uuidString)", isDirectory: true)
        let bottles = root.appendingPathComponent("bottles", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bottles.appendingPathComponent("epic", isDirectory: true),
            withIntermediateDirectories: true
        )
        var plan = UninstallPlanBuilder.makeDefaultPlan(
            context: UninstallPlanBuilder.Context(
                appSupportURL: root,
                bottlesURL: bottles,
                enginesURL: root.appendingPathComponent("engines"),
                cacheURL: root.appendingPathComponent("cache"),
                configURL: root.appendingPathComponent("config.json"),
                home: root
            )
        )
        plan.selectAll()
        XCTAssertTrue(plan.isEverythingSelected)
        XCTAssertEqual(plan.bottlesTriState, .on)
        plan.deselectAll()
        XCTAssertTrue(plan.isNothingSelected)
        try? FileManager.default.removeItem(at: root)
    }

    func testMixedBottleSelection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-mix-\(UUID().uuidString)", isDirectory: true)
        let bottles = root.appendingPathComponent("bottles", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bottles.appendingPathComponent("steam", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: bottles.appendingPathComponent("epic", isDirectory: true),
            withIntermediateDirectories: true
        )
        var plan = UninstallPlanBuilder.makeDefaultPlan(
            context: UninstallPlanBuilder.Context(
                appSupportURL: root,
                bottlesURL: bottles,
                enginesURL: root.appendingPathComponent("engines"),
                cacheURL: root.appendingPathComponent("cache"),
                configURL: root.appendingPathComponent("config.json"),
                home: root
            )
        )
        XCTAssertEqual(plan.bottles.count, 2)
        plan.setBottleSelected(id: .store("steam"), selected: true)
        XCTAssertEqual(plan.bottlesTriState, .mixed)
        XCTAssertTrue(plan.hasSelectedBottle)
        try? FileManager.default.removeItem(at: root)
    }

    func testPreferencesPlanIncludesConfigJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-prefs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config.json")
        try "{}".data(using: .utf8)!.write(to: config)
        let prefs = UninstallPlanBuilder.makePreferencesTarget(
            context: UninstallPlanBuilder.Context(
                appSupportURL: root,
                bottlesURL: root.appendingPathComponent("bottles"),
                enginesURL: root.appendingPathComponent("engines"),
                cacheURL: root.appendingPathComponent("cache"),
                configURL: config,
                home: root
            ),
            selected: true
        )
        XCTAssertTrue(prefs.urls.contains(where: { $0.lastPathComponent == "config.json" }))
        try? FileManager.default.removeItem(at: root)
    }
}

final class UninstallProcessScoutTests: XCTestCase {
    func testDisplayNameForSteamExe() {
        let name = UninstallProcessScout.displayName(
            for: #"WINEPREFIX=/tmp/bottles/steam/prefix wine64 C:\Program Files (x86)\Steam\steam.exe"#,
            pid: 42
        )
        XCTAssertEqual(name, "Steam (Windows)")
    }

    func testDownloadPlaceholdersAreWillCancel() {
        let stubs = UninstallProcessScout.downloadPlaceholders([
            .init(name: "Download: DXVK 2.7")
        ])
        XCTAssertEqual(stubs.count, 1)
        XCTAssertEqual(stubs[0].status, .willCancel)
        XCTAssertEqual(stubs[0].kind, .download)
    }

    func testDiscoverWineProcessesUsesStubRows() {
        let prefix = "/tmp/vermut-bottles/steam/prefix"
        let rows: [PrefixProcessTerminator.ProcessRow] = [
            .init(
                pid: 4812,
                ppid: 1,
                pgid: 4812,
                command: "WINEPREFIX=\(prefix) /engines/grapple-wine/bin/wine64 steam.exe"
            ),
            .init(
                pid: 99,
                ppid: 1,
                pgid: 99,
                command: "/Applications/Steam.app/Contents/MacOS/steam_osx"
            ),
        ]
        let found = UninstallProcessScout.discoverWineProcesses(
            prefixes: [prefix],
            bottleLabelForPrefix: { _ in "Steam bottle" },
            rows: rows,
            enginesRoot: "/engines",
            bottlesRoot: "/tmp/vermut-bottles",
            executablePathProvider: { _ in nil },
            openPathsProvider: { _ in [] },
            currentPID: 1
        )
        XCTAssertTrue(found.contains { $0.pid == 4812 })
        XCTAssertFalse(found.contains { $0.pid == 99 }, "Native Steam must never appear")
    }

    func testSoftQuitInvokesWineserverWithoutSignals() {
        let prefix = "/tmp/prefix-a"
        var ran: [(String, String)] = []
        UninstallProcessScout.softQuit(
            prefixes: [prefix],
            engineForPrefix: { _ in .grappleWine },
            wineserverForEngine: { _ in URL(fileURLWithPath: "/usr/bin/true") },
            timeout: 1,
            sleeper: { _ in },
            wineserverRunner: { wineserver, p, _ in
                ran.append((wineserver.path, p))
            }
        )
        XCTAssertEqual(ran.count, 1)
        XCTAssertEqual(ran.first?.1, prefix)
    }

    func testForceQuitSendsTermThenKill() {
        var signals: [(pid_t, Int32)] = []
        let alive = Set<pid_t>([7])
        _ = UninstallProcessScout.forceQuit(
            pids: [7],
            termGraceSeconds: 0,
            killGraceSeconds: 0,
            sleeper: { _ in },
            signalSender: { pid, sig in
                signals.append((pid, sig))
                if sig == 0 { return alive.contains(pid) ? 0 : -1 }
                return 0
            }
        )
        XCTAssertEqual(signals.first?.1, SIGTERM)
        XCTAssertTrue(signals.contains { $0.1 == SIGKILL })
    }
}

final class UninstallExecutorSafetyTests: XCTestCase {
    func testTrashSkipsOutsideWhitelist() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-exec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-outside-\(UUID().uuidString)")
        try "keep-me".data(using: .utf8)!.write(to: outside)

        let target = UninstallTarget(
            id: "caches",
            category: .caches,
            displayName: "Caches",
            urls: [outside],
            byteCount: 8,
            isSelected: true
        )
        let plan = UninstallPlan(
            bottles: [],
            engines: UninstallTarget(
                id: "engines",
                category: .engines,
                displayName: "Engines",
                urls: [],
                isSelected: false
            ),
            caches: target,
            logs: UninstallTarget(
                id: "logs",
                category: .logs,
                displayName: "Logs",
                urls: [],
                isSelected: false
            ),
            preferences: UninstallTarget(
                id: "preferences",
                category: .preferences,
                displayName: "Preferences",
                urls: [],
                isSelected: false
            )
        )

        let summary = UninstallExecutor.run(
            plan: plan,
            options: UninstallExecutor.Options(
                appSupportURL: root,
                home: root,
                clearUserDefaults: false
            )
        )
        XCTAssertTrue(summary.hasFailures)
        XCTAssertEqual(summary.failureResults.first?.outcome, .skipped)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }

    func testTrashMovesWhitelistedFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-trash-\(UUID().uuidString)", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let file = cache.appendingPathComponent("components.json")
        try "{}".data(using: .utf8)!.write(to: file)

        let plan = UninstallPlan(
            bottles: [],
            engines: UninstallTarget(
                id: "engines", category: .engines, displayName: "Engines", urls: [], isSelected: false
            ),
            caches: UninstallTarget(
                id: "caches",
                category: .caches,
                displayName: "Caches",
                urls: [cache],
                byteCount: 2,
                isSelected: true
            ),
            logs: UninstallTarget(
                id: "logs", category: .logs, displayName: "Logs", urls: [], isSelected: false
            ),
            preferences: UninstallTarget(
                id: "preferences",
                category: .preferences,
                displayName: "Preferences",
                urls: [],
                isSelected: false
            )
        )

        let summary = UninstallExecutor.run(
            plan: plan,
            options: UninstallExecutor.Options(
                appSupportURL: root,
                home: root,
                clearUserDefaults: false
            )
        )
        #if os(macOS)
        XCTAssertFalse(summary.hasFailures)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        #else
        _ = summary
        #endif
        try? FileManager.default.removeItem(at: root)
    }

    func testRemovalOrderExcludesApp() {
        let plan = UninstallPlan(
            bottles: [
                UninstallTarget(
                    id: "bottle-steam",
                    category: .bottles,
                    bottleID: .store("steam"),
                    displayName: "Steam",
                    urls: [],
                    isSelected: true
                )
            ],
            engines: UninstallTarget(
                id: "engines", category: .engines, displayName: "Engines", urls: [], isSelected: true
            ),
            caches: UninstallTarget(
                id: "caches", category: .caches, displayName: "Caches", urls: [], isSelected: true
            ),
            logs: UninstallTarget(
                id: "logs", category: .logs, displayName: "Logs", urls: [], isSelected: true
            ),
            preferences: UninstallTarget(
                id: "preferences",
                category: .preferences,
                displayName: "Preferences",
                urls: [],
                isSelected: true
            )
        )
        let ids = UninstallExecutor.orderedTargets(from: plan).map(\.id)
        XCTAssertEqual(ids, ["logs", "caches", "engines", "bottle-steam", "preferences"])
        XCTAssertFalse(ids.contains("app"))
    }

    func testFinalizeCleansEmptyDirsConfigAndCustomIndex() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-finalize-\(UUID().uuidString)", isDirectory: true)
        let bottles = root.appendingPathComponent("bottles", isDirectory: true)
        let engines = root.appendingPathComponent("engines", isDirectory: true)
        try FileManager.default.createDirectory(at: bottles, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: engines, withIntermediateDirectories: true)
        try "{}".data(using: .utf8)!.write(to: root.appendingPathComponent("config.json"))
        try "[]".data(using: .utf8)!.write(
            to: root.appendingPathComponent(CustomBottleStore.indexFileName)
        )

        let plan = UninstallPlan(
            bottles: [
                UninstallTarget(
                    id: "bottle-steam",
                    category: .bottles,
                    bottleID: .store("steam"),
                    displayName: "Steam",
                    urls: [bottles.appendingPathComponent("steam")],
                    isSelected: true
                )
            ],
            engines: UninstallTarget(
                id: "engines", category: .engines, displayName: "Engines",
                urls: [engines], isSelected: true
            ),
            caches: UninstallTarget(
                id: "caches", category: .caches, displayName: "Caches", urls: [], isSelected: true
            ),
            logs: UninstallTarget(
                id: "logs", category: .logs, displayName: "Logs", urls: [], isSelected: true
            ),
            preferences: UninstallTarget(
                id: "preferences", category: .preferences, displayName: "Preferences",
                urls: [root.appendingPathComponent("config.json")], isSelected: true
            )
        )

        let allowed = UninstallPathPolicy.allowedPrefixes(
            appSupport: root,
            appBundle: nil,
            home: root
        )
        #if os(macOS)
        UninstallExecutor.finalizeAppSupportCleanup(
            plan: plan,
            appSupport: root,
            allowed: allowed,
            home: root,
            fileManager: .default
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        #else
        _ = (plan, allowed)
        try? FileManager.default.removeItem(at: root)
        #endif
    }

    func testPersistenceGateBlocksConfigRewrite() {
        UninstallPersistenceGate.resetForTests()
        defer { UninstallPersistenceGate.resetForTests() }
        XCTAssertFalse(UninstallPersistenceGate.writesSuppressed)
        UninstallPersistenceGate.beginWipe()
        XCTAssertTrue(UninstallPersistenceGate.writesSuppressed)
        XCTAssertFalse(
            UninstallPersistenceGate.immediateExitArmed,
            "beginWipe alone must not arm hard-exit (normal Quit after cancel)"
        )
    }

    func testImmediateExitArmIsProcessLocalAndIndependentOfAppState() {
        UninstallPersistenceGate.resetForTests()
        defer { UninstallPersistenceGate.resetForTests() }
        XCTAssertFalse(UninstallPersistenceGate.immediateExitArmed)
        XCTAssertFalse(UninstallPersistenceGate.shouldSkipWineCleanupAndExit)
        UninstallPersistenceGate.armImmediateExit()
        XCTAssertTrue(UninstallPersistenceGate.immediateExitArmed)
        XCTAssertTrue(UninstallPersistenceGate.writesSuppressed)
        XCTAssertTrue(UninstallPersistenceGate.shouldSkipWineCleanupAndExit)
    }

    func testBeginWipeImpliesSkipWineCleanupWithoutArmingExitYet() {
        UninstallPersistenceGate.resetForTests()
        defer { UninstallPersistenceGate.resetForTests() }
        UninstallPersistenceGate.beginWipe()
        // Delegate may hard-exit when writes are suppressed (wipe already ran).
        XCTAssertTrue(UninstallPersistenceGate.shouldSkipWineCleanupAndExit)
        XCTAssertFalse(UninstallPersistenceGate.immediateExitArmed)
    }

}
