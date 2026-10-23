import XCTest
@testable import CaskLauncherCore

final class SteamReadinessTests: XCTestCase {
    private func makeDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    func testBootstrapperOnlyIsNotReady() throws {
        let d = try makeDir()
        try touch(d.appendingPathComponent("steam.exe"))
        XCTAssertFalse(SteamReadiness.isClientReady(steamDirectory: d))
        try touch(d.appendingPathComponent("SteamUI.dll"))
        XCTAssertFalse(SteamReadiness.isClientReady(steamDirectory: d))
    }

    func testUpdatedClientIsReady() throws {
        let d = try makeDir()
        try touch(d.appendingPathComponent("steam.exe"))
        try touch(d.appendingPathComponent("SteamUI.dll"))
        try touch(d.appendingPathComponent("bin/cef/cef.win7x64/steamwebhelper.exe"))
        XCTAssertTrue(SteamReadiness.isClientReady(steamDirectory: d))
    }

    func testPrefixLookupUsesProgramFilesX86() throws {
        let p = try makeDir()
        let s = p.appendingPathComponent("drive_c/Program Files (x86)/Steam")
        try touch(s.appendingPathComponent("steam.exe"))
        XCTAssertFalse(SteamReadiness.isClientReady(inPrefix: p))
        try touch(s.appendingPathComponent("SteamUI.dll"))
        try touch(s.appendingPathComponent("bin/cef/cef.win64/steamwebhelper.exe"))
        XCTAssertTrue(SteamReadiness.isClientReady(inPrefix: p))
    }

    func testUpdatingPhaseIsInProgressAndNotOverriddenByRefresh() {
        let s = StoreStatus.installing(.updatingClient)
        XCTAssertTrue(s.isInstallInProgress)
        XCTAssertEqual(StoreStatus.refreshed(current: s, isRunning: false, isInstalled: true), s)
    }

    func testFirstLaunchIsRetried() {
        XCTAssertGreaterThan(SteamReadiness.firstLaunchAttempts, 1)
    }

    func testBootstrapRelaunchWhenProcessDiesBeforeClientReady() {
        XCTAssertTrue(
            SteamReadiness.shouldRelaunchBootstrap(
                isRunning: false,
                clientReady: false,
                relaunchesSoFar: 0
            )
        )
        XCTAssertTrue(
            SteamReadiness.shouldRelaunchBootstrap(
                isRunning: false,
                clientReady: false,
                relaunchesSoFar: 2
            )
        )
        XCTAssertFalse(
            SteamReadiness.shouldRelaunchBootstrap(
                isRunning: false,
                clientReady: false,
                relaunchesSoFar: SteamReadiness.bootstrapRelaunchAttempts
            )
        )
        XCTAssertFalse(
            SteamReadiness.shouldRelaunchBootstrap(
                isRunning: true,
                clientReady: false,
                relaunchesSoFar: 0
            )
        )
        XCTAssertFalse(
            SteamReadiness.shouldRelaunchBootstrap(
                isRunning: false,
                clientReady: true,
                relaunchesSoFar: 0
            )
        )
    }

    func testSteamClientInstalledRequiresFullClientNotBootstrapper() throws {
        let p = try makeDir()
        let s = p.appendingPathComponent("drive_c/Program Files (x86)/Steam")
        try touch(s.appendingPathComponent("steam.exe"))
        XCTAssertFalse(SteamReadiness.isSteamClientInstalled(inPrefix: p))
        try touch(s.appendingPathComponent("SteamUI.dll"))
        try touch(s.appendingPathComponent("bin/cef/cef.win64/steamwebhelper.exe"))
        XCTAssertTrue(SteamReadiness.isSteamClientInstalled(inPrefix: p))
    }
}
