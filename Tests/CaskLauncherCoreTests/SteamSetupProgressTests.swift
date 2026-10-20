import XCTest
@testable import CaskLauncherCore

final class SteamSetupProgressTests: XCTestCase {
    private func inputs(_ log: String?, quiet: TimeInterval? = 60, files: Bool = false, helper: Bool = false, window: Bool = false) -> SteamSetupInputs {
        SteamSetupInputs(bootstrap: log.map(SteamBootstrapLog.parse), secondsSinceLogChange: quiet, clientFilesReady: files, webhelperRunning: helper, windowVisible: window)
    }

    func testFirstStartBeforeAnyUpdateActivity() {
        let log = "[t] Startup - updater built May 20 2024\n[t] Verifying installation...\n[t] Verification complete\n"
        XCTAssertEqual(SteamSetupEvaluator.stage(inputs(nil)), .firstStart)
        XCTAssertEqual(SteamSetupEvaluator.stage(inputs(log)), .firstStart)
    }

    func testDownloadProgressIsParsed() {
        let log = "[t] Checking for available updates...\n[t] Downloading update (165,627 of 238,534 KB)...\n"
        guard case .updating(let p?) = SteamSetupEvaluator.stage(inputs(log)) else { return XCTFail() }
        XCTAssertEqual(p, 165_627.0 / 238_534.0, accuracy: 0.0001)
    }

    func testStuckManifestIsStillUpdatingNotReady() {
        let log = "[t] Verification complete\n[t] Checking for available updates...\n[t] Downloading manifest: https://cdn.steamstatic.com/client/steam_client_win32\n"
        XCTAssertEqual(SteamSetupEvaluator.stage(inputs(log, files: false, helper: true, window: true)), .updating(progress: nil))
    }

    func testCompletedButNoWindowIsFinishing() {
        let log = "[t] Downloading update (238,534 of 238,534 KB)...\n[t] Download complete.\n"
        XCTAssertEqual(SteamSetupEvaluator.stage(inputs(log, files: true, helper: true, window: false)), .finishing)
        XCTAssertEqual(SteamSetupEvaluator.stage(inputs(log, files: true, helper: false, window: true)), .finishing)
    }

    func testRecentLogActivityBlocksReady() {
        let log = "[t] Download complete.\n"
        XCTAssertEqual(SteamSetupEvaluator.stage(inputs(log, quiet: 3, files: true, helper: true, window: true)), .finishing)
    }

    func testReadyNeedsCompletionQuietHelperAndWindow() {
        let log = "[t] Downloading update (1 of 2 KB)...\n[t] Download complete.\n[t] Verification complete\n"
        XCTAssertEqual(SteamSetupEvaluator.stage(inputs(log, quiet: 30, files: true, helper: true, window: true)), .ready)
    }

    func testNewCheckAfterCompletionGoesBackToUpdating() {
        let log = "[t] Download complete.\n[t] Checking for available updates...\n"
        XCTAssertEqual(SteamSetupEvaluator.stage(inputs(log, files: true, helper: true, window: true)), .updating(progress: 1))
    }

    func testStallThresholdAndLabels() {
        XCTAssertFalse(SteamSetupEvaluator.isStalled(secondsSinceProgress: 60))
        XCTAssertTrue(SteamSetupEvaluator.isStalled(secondsSinceProgress: 181))
        XCTAssertEqual(SteamSetupStage.updating(progress: 0.5).label, "Updating Steam… 50%")
        XCTAssertTrue(SteamSetupEvaluator.isBottleWebhelper(#"C:\Program Files (x86)\Steam\bin\cef\cef.win64\steamwebhelper.exe --type=gpu"#))
        XCTAssertFalse(SteamSetupEvaluator.isBottleWebhelper("/Users/x/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steamwebhelper"))
    }
}
