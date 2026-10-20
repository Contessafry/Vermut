import XCTest
@testable import CaskLauncherCore

final class StoreStatusRefreshTests: XCTestCase {
    func testInstallInProgressIsNotOverriddenByInstalledExe() {
        XCTAssertEqual(StoreStatus.refreshed(current: .installing(.settingUp), isRunning: false, isInstalled: true), .installing(.settingUp))
        XCTAssertEqual(StoreStatus.refreshed(current: .downloading(progress: 0.4), isRunning: false, isInstalled: true), .downloading(progress: 0.4))
    }
    func testRunningWins() {
        XCTAssertEqual(StoreStatus.refreshed(current: .installing(.awaitingWindow), isRunning: true, isInstalled: true), .running)
    }
    func testIdleStates() {
        XCTAssertEqual(StoreStatus.refreshed(current: nil, isRunning: false, isInstalled: true), .installed)
        XCTAssertEqual(StoreStatus.refreshed(current: .installed, isRunning: false, isInstalled: false), .notInstalled)
        XCTAssertEqual(StoreStatus.refreshed(current: .error("x"), isRunning: false, isInstalled: false), .error("x"))
    }
}

final class SteamSyncEnvironmentTests: XCTestCase {
    func testSteamLaunchUsesTheSharedSyncEnvironment() {
        let recipe = StoreLaunchRecipe.build(
            store: .steam,
            executable: URL(fileURLWithPath: "/tmp/Steam/steam.exe"),
            wineLibDir: URL(fileURLWithPath: "/tmp/lib")
        )
        for (key, value) in StoreLaunchRecipe.syncEnvironment(for: .steam) {
            XCTAssertEqual(recipe.environment[key], value, key)
        }
        XCTAssertEqual(StoreLaunchRecipe.syncEnvironment(for: .steam)["WINEMSYNC"], "1")
    }
}

final class GOGFirstRunTests: XCTestCase {
    func testFindsOnlyFirstRunInThisPrefix() {
        let prefix = "/Users/u/Library/Application Support/Vermut/bottles/gog/prefix"
        let lines = [
            "  4911 C:\\Program Files\\GOG Galaxy\\GalaxyClient.exe /firstRun /installationSource=usedefault WINEPREFIX=\(prefix) HOME=/Users/u",
            "  4912 C:\\Program Files\\GOG Galaxy\\GalaxyClient.exe WINEPREFIX=\(prefix) HOME=/Users/u",
            "  4913 C:\\Program Files\\GOG Galaxy\\GalaxyClient.exe /firstRun WINEPREFIX=/other/prefix HOME=/Users/u",
            "  4914 C:\\setup_galaxy.tmp /SL5 WINEPREFIX=\(prefix)"
        ]
        XCTAssertEqual(GOGFirstRun.pids(in: lines, prefixPath: prefix), [4911])
    }

    func testSteamFirstRunUpdateIsNotOverriddenByRunning() {
        XCTAssertEqual(StoreStatus.refreshed(current: .installing(.updatingClient), isRunning: true, isInstalled: true), .installing(.updatingClient))
    }
}
