import XCTest
@testable import CaskLauncherCore

final class LeftoverFixesTests: XCTestCase {
    let prefix = "/Users/x/Library/Application Support/Vermut/bottles/steam/prefix"

    func testBottleSteamRunningWithWindowsPathAndOurWineserver() {
        let lines = [
            #"123 C:\Program Files (x86)\Steam\steam.exe "#,
            "124 /Users/x/Library/Application Support/Vermut/engines/w/bin/wineserver WINEPREFIX=\(prefix)",
        ]
        XCTAssertTrue(PrefixRuntime.isBottleSteamRunning(prefixPath: prefix, processLines: lines))
    }

    func testNotRunningWhenClosedOrOnlyNativeSteam() {
        XCTAssertFalse(PrefixRuntime.isBottleSteamRunning(prefixPath: prefix, processLines: [
            "1 /Users/x/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx",
        ]))
        XCTAssertFalse(PrefixRuntime.isBottleSteamRunning(prefixPath: prefix, processLines: [
            "124 /Users/x/Library/Application Support/Vermut/engines/w/bin/wineserver WINEPREFIX=\(prefix)",
        ]))
    }

    func testRunningMapsToNeutralRunningAndBackToInstalled() {
        XCTAssertEqual(StoreStatus.refreshed(current: .installed, isRunning: true, isInstalled: true), .running)
        XCTAssertEqual(StoreStatus.refreshed(current: .running, isRunning: false, isInstalled: true), .installed)
    }

    func testLibraryEmptyTextDoesNotOfferGOG() {
        XCTAssertFalse(VermutProject.libraryEmptyMessage.contains("GOG"))
        XCTAssertTrue(VermutProject.libraryEmptyMessage.contains("Steam or Epic"))
    }
}
