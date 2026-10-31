import XCTest
@testable import CaskLauncherCore

final class ModelsTests: XCTestCase {
    
    func testGameStoreIdentifiers() {
        XCTAssertEqual(GameStore.steam.identifier, "steam")
        XCTAssertEqual(GameStore.epic.identifier, "epic")
        XCTAssertEqual(GameStore.gog.identifier, "gog")
    }
    
    func testGameStoreInstallerURLs() {
        XCTAssertTrue(GameStore.steam.installerURL.contains("SteamSetup.exe"))
        XCTAssertTrue(GameStore.epic.installerURL.contains("legendary"))
        XCTAssertTrue(GameStore.gog.installerURL.contains("setup_galaxy"))
        XCTAssertFalse(GameStore.gog.installerURL.contains("GOG_Galaxy_2.0.exe"))
    }
    
    func testGameStoreExecutablePaths() {
        XCTAssertTrue(GameStore.steam.executablePath.contains("steam.exe"))
        XCTAssertTrue(GameStore.epic.executablePath.contains("EpicGamesLauncher.exe"))
        XCTAssertTrue(GameStore.epic.executablePath.contains("Win64"))
        XCTAssertTrue(GameStore.gog.executablePath.contains("GalaxyClient.exe"))
    }
    
    func testSteamLaunchEnvironmentDoesNotDisableWebHelper() {
        let env = GameStore.steam.launchEnvironment
        XCTAssertNotEqual(env["WINEDLLOVERRIDES"], "steamwebhelper.exe=d")
    }
    
    func testAppConfiguration() {
        let config = AppConfiguration()
        XCTAssertEqual(config.defaultGraphicsBackend, GraphicsBackend.dxmt.rawValue)
        XCTAssertEqual(config.defaultEngine, WineEngine.grappleWine.rawValue)
        XCTAssertTrue(config.enableHiDPI)
        XCTAssertEqual(config.windowsVersion, "win10")
    }
    
    func testVermutProjectIdentityIsPublicAndDoesNotSayCaskLauncher() {
        XCTAssertEqual(VermutProject.name, "Vermut")
        // Must match the VERSION file build.sh stamps into Info.plist (the
        // sidebar showed v1.1.2 inside a 1.1.3 bundle once).
        let versionFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("VERSION")
        let fileVersion = (try? String(contentsOf: versionFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(VermutProject.version, fileVersion)
        XCTAssertEqual(VermutProject.tagline, "Pour. Click. Play.")
        XCTAssertEqual(VermutProject.githubDisplay, "github.com/Contessafry/Vermut")
        XCTAssertEqual(VermutProject.githubURL.host, "github.com")
        XCTAssertTrue(VermutProject.githubURL.path.contains("Contessafry/Vermut"))
        XCTAssertTrue(VermutProject.licenseURL.path.contains("LICENSE"))
        XCTAssertFalse(VermutProject.name.localizedCaseInsensitiveContains("casklauncher"))
        XCTAssertFalse(VermutProject.tagline.localizedCaseInsensitiveContains("casklauncher"))
        XCTAssertFalse(VermutProject.githubDisplay.localizedCaseInsensitiveContains("casklauncher"))
        XCTAssertFalse(VermutProject.githubDisplay.localizedCaseInsensitiveContains("vermut-app"))
    }

    func testWineEngineUserFacingNamesHideGrappleWine() {
        XCTAssertEqual(WineEngine.grappleWine.userFacingName, "Vermut Wine")
        XCTAssertEqual(WineEngine.staging.userFacingName, "Wine Staging")
        XCTAssertEqual(WineEngine.devel.userFacingName, "Wine Devel")
        XCTAssertEqual(WineEngine.staging.userFacingName(version: "11.20"), "Wine Staging 11.20")
        XCTAssertFalse(WineEngine.staging.userFacingName.contains("11.18"))
        XCTAssertEqual(WineEngine.staging.subtitle, "Gcenx · WineHQ · experimental patches")
        XCTAssertTrue(WineEngine.staging.requiresGStreamer)
        XCTAssertFalse(WineEngine.grappleWine.requiresGStreamer)
        for engine in WineEngine.allCases {
            XCTAssertFalse(
                engine.userFacingName.localizedCaseInsensitiveContains("grapple"),
                "UI must not show grapple-wine: \(engine.userFacingName)"
            )
            XCTAssertFalse(
                engine.displayName.localizedCaseInsensitiveContains("grapple"),
                "displayName is used in pickers: \(engine.displayName)"
            )
        }
        XCTAssertEqual(WineEngine.grappleWine.rawValue, "grapple-wine")
    }

    func testInstallerPhasesAreDistinctFromDownloading() {
        XCTAssertNotEqual(StoreStatus.downloading(progress: 1), StoreStatus.installing(.settingUp))
        XCTAssertNotEqual(StoreStatus.installing(.settingUp), StoreStatus.installing(.awaitingWindow))
        XCTAssertTrue(StoreStatus.downloading(progress: 0.4).isInstallInProgress)
        XCTAssertTrue(StoreStatus.installing(.settingUp).isInstallInProgress)
        XCTAssertTrue(StoreStatus.installing(.awaitingWindow).isInstallInProgress)
        XCTAssertFalse(StoreStatus.installed.isInstallInProgress)
    }

    func testGraphicsBackendCases() {
        XCTAssertEqual(GraphicsBackend.allCases.count, 4)
        XCTAssertTrue(GraphicsBackend.allCases.contains(.dxmt))
        XCTAssertTrue(GraphicsBackend.allCases.contains(.dxvk))
        XCTAssertTrue(GraphicsBackend.allCases.contains(.d3dmetal))
        XCTAssertTrue(GraphicsBackend.allCases.contains(.wined3d))
    }
}
