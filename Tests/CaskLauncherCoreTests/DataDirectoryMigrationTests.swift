import XCTest
@testable import CaskLauncherCore

final class DataDirectoryMigrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-migrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    func testPrefersVermutWhenBothExist() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Vermut/bottles/steam"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("CaskLauncher"),
            withIntermediateDirectories: true
        )
        let outcome = DataDirectoryMigration.resolve(
            applicationSupport: root,
            wineRunningInLegacy: { _ in true }
        )
        XCTAssertEqual(outcome.appSupportURL.lastPathComponent, "Vermut")
        XCTAssertFalse(outcome.migrated)
        XCTAssertFalse(outcome.deferred)
    }

    func testCreatesVermutPathWhenNeitherExists() {
        let outcome = DataDirectoryMigration.resolve(
            applicationSupport: root,
            processLister: { [] }
        )
        XCTAssertEqual(outcome.appSupportURL.lastPathComponent, "Vermut")
        XCTAssertFalse(outcome.migrated)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outcome.appSupportURL.path))
    }

    func testMigratesLegacyWhenNoWineIsRunning() throws {
        let legacy = root.appendingPathComponent("CaskLauncher")
        let bottle = legacy.appendingPathComponent("bottles/steam/prefix", isDirectory: true)
        try FileManager.default.createDirectory(at: bottle, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: bottle.appendingPathComponent("system.reg"))

        let outcome = DataDirectoryMigration.resolve(
            applicationSupport: root,
            wineRunningInLegacy: { _ in false }
        )
        XCTAssertTrue(outcome.migrated)
        XCTAssertEqual(outcome.appSupportURL.lastPathComponent, "Vermut")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: outcome.appSupportURL.appendingPathComponent("bottles/steam/prefix/system.reg").path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testDefersWhenWineIsRunning() throws {
        let legacy = root.appendingPathComponent("CaskLauncher")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        let outcome = DataDirectoryMigration.resolve(
            applicationSupport: root,
            wineRunningInLegacy: { _ in true }
        )
        XCTAssertTrue(outcome.deferred)
        XCTAssertFalse(outcome.migrated)
        XCTAssertEqual(outcome.appSupportURL.lastPathComponent, "CaskLauncher")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testFallsBackWhenMoveFails() throws {
        let legacy = root.appendingPathComponent("CaskLauncher")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        // Occupy the destination name with a file so moveItem fails.
        try Data("blocked".utf8).write(to: root.appendingPathComponent("Vermut"))

        let outcome = DataDirectoryMigration.resolve(
            applicationSupport: root,
            wineRunningInLegacy: { _ in false }
        )
        XCTAssertTrue(outcome.usedFallback)
        XCTAssertEqual(outcome.appSupportURL.lastPathComponent, "CaskLauncher")
    }

    func testBottlesHaveWineProcessMatchesPrefix() throws {
        let bottles = root.appendingPathComponent("bottles", isDirectory: true)
        let steam = bottles.appendingPathComponent("steam", isDirectory: true)
        let prefix = steam.appendingPathComponent("prefix", isDirectory: true)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)

        var listed: [[String]] = []
        let wineLine = "WINEPREFIX=\(prefix.path) /opt/wine/bin/wine SteamSetup.exe"
        XCTAssertTrue(
            DataDirectoryMigration.bottlesHaveWineProcess(
                bottlesURL: bottles,
                processLister: {
                    listed.append([wineLine])
                    return [wineLine]
                },
                fileManager: .default
            )
        )
        XCTAssertEqual(listed.count, 1)
        XCTAssertFalse(
            DataDirectoryMigration.bottlesHaveWineProcess(
                bottlesURL: bottles,
                processLister: { ["some other process"] },
                fileManager: .default
            )
        )
    }

    func testResolveDefersUsingInjectedProcessLister() throws {
        let legacy = root.appendingPathComponent("CaskLauncher")
        let prefix = legacy
            .appendingPathComponent("bottles", isDirectory: true)
            .appendingPathComponent("steam", isDirectory: true)
            .appendingPathComponent("prefix", isDirectory: true)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)

        let outcome = DataDirectoryMigration.resolve(
            applicationSupport: root,
            processLister: { ["WINEPREFIX=\(prefix.path) /opt/wine/bin/wine64 EpicGamesLauncher.exe"] }
        )
        XCTAssertTrue(outcome.deferred)
        XCTAssertFalse(outcome.migrated)
        XCTAssertEqual(outcome.appSupportURL.lastPathComponent, "CaskLauncher")
    }

    func testDeferredThenIdleLaunchMigrates() throws {
        let legacy = root.appendingPathComponent("CaskLauncher")
        let bottle = legacy.appendingPathComponent("bottles/steam/prefix", isDirectory: true)
        try FileManager.default.createDirectory(at: bottle, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: bottle.appendingPathComponent("system.reg"))

        let deferred = DataDirectoryMigration.resolve(
            applicationSupport: root,
            wineRunningInLegacy: { _ in true }
        )
        XCTAssertTrue(deferred.deferred)
        XCTAssertEqual(deferred.appSupportURL.lastPathComponent, "CaskLauncher")
        XCTAssertEqual(
            DataDirectoryMigration.displayPath(
                of: deferred.appSupportURL.appendingPathComponent("bottles/steam"),
                home: root.path,
                deferred: true
            ),
            "~/CaskLauncher/bottles/steam\nWill move to Vermut on next restart"
        )

        let moved = DataDirectoryMigration.resolve(
            applicationSupport: root,
            wineRunningInLegacy: { _ in false }
        )
        XCTAssertTrue(moved.migrated)
        XCTAssertFalse(moved.deferred)
        XCTAssertEqual(moved.appSupportURL.lastPathComponent, "Vermut")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: moved.appSupportURL.appendingPathComponent("bottles/steam/prefix/system.reg").path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(
            DataDirectoryMigration.displayPath(
                of: moved.appSupportURL.appendingPathComponent("bottles/steam"),
                home: root.path,
                deferred: false
            ),
            "~/Vermut/bottles/steam"
        )
    }

    func testEmptyVermutDoesNotBlockLegacyMigration() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Vermut"),
            withIntermediateDirectories: true
        )
        let legacy = root.appendingPathComponent("CaskLauncher")
        let bottle = legacy.appendingPathComponent("bottles/steam/prefix", isDirectory: true)
        try FileManager.default.createDirectory(at: bottle, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: bottle.appendingPathComponent("system.reg"))

        let deferred = DataDirectoryMigration.resolve(
            applicationSupport: root,
            wineRunningInLegacy: { _ in true }
        )
        XCTAssertTrue(deferred.deferred)
        XCTAssertEqual(deferred.appSupportURL.lastPathComponent, "CaskLauncher")

        let moved = DataDirectoryMigration.resolve(
            applicationSupport: root,
            wineRunningInLegacy: { _ in false }
        )
        XCTAssertTrue(moved.migrated)
        XCTAssertEqual(moved.appSupportURL.lastPathComponent, "Vermut")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: moved.appSupportURL.appendingPathComponent("bottles/steam/prefix/system.reg").path
            )
        )
    }
}

final class PrefixRuntimeWineProcessTests: XCTestCase {
    func testHasWineProcessRequiresPrefixAndWine() {
        let prefix = "/tmp/bottle/prefix"
        XCTAssertTrue(
            PrefixRuntime.hasWineProcess(
                prefixPath: prefix,
                processLines: ["WINEPREFIX=\(prefix) wineserver -f"]
            )
        )
        XCTAssertTrue(
            PrefixRuntime.hasWineProcess(
                prefixPath: prefix,
                processLines: ["WINEPREFIX=\(prefix) /opt/wine/bin/wine SteamSetup.exe"]
            )
        )
        XCTAssertFalse(
            PrefixRuntime.hasWineProcess(
                prefixPath: prefix,
                processLines: ["WINEPREFIX=\(prefix) /usr/bin/true"]
            )
        )
        XCTAssertFalse(
            PrefixRuntime.hasWineProcess(
                prefixPath: prefix,
                processLines: ["/opt/wine/bin/wine SteamSetup.exe"]
            )
        )
    }
}
