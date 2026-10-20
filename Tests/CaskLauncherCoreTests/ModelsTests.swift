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
        XCTAssertEqual(VermutProject.version, "1.1.2")
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
        XCTAssertEqual(WineEngine.grappleWine.userFacingName, "Vermut Wine 11 (DXMT build)")
        XCTAssertEqual(WineEngine.staging.userFacingName, "Wine Staging 11")
        XCTAssertEqual(WineEngine.devel.userFacingName, "Wine Devel 11")
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
