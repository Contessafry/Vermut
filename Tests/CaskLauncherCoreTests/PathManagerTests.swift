import XCTest
@testable import CaskLauncherCore

final class PathManagerTests: XCTestCase {
    
    func testPathManagerSingleton() {
        let manager1 = PathManager.shared
        let manager2 = PathManager.shared
        XCTAssertTrue(manager1 === manager2)
    }
    
    func testAppSupportPath() {
        let manager = PathManager.shared
        let folder = manager.appSupportURL.lastPathComponent
        XCTAssertTrue(folder == "Vermut" || folder == "CaskLauncher")
        if manager.migrationDeferred {
            XCTAssertEqual(folder, "CaskLauncher")
        }
        #if os(macOS)
        XCTAssertTrue(manager.appSupportURL.path.contains("Application Support"))
        #endif
    }
    
    func testPrefixPaths() {
        let manager = PathManager.shared
        
        for store in GameStore.allCases {
            let prefixURL = manager.prefixURL(for: store)
            XCTAssertTrue(prefixURL.path.contains(store.identifier))
        }
    }
    
    func testLogPaths() {
        let manager = PathManager.shared
        
        for store in GameStore.allCases {
            let logURL = manager.logURL(for: store)
            XCTAssertTrue(logURL.path.hasSuffix("\(store.identifier).log"))
        }
    }
    
    func testInstallerPaths() {
        let manager = PathManager.shared
        
        let steamInstaller = manager.installerURL(for: .steam)
        XCTAssertTrue(steamInstaller.path.hasSuffix("SteamSetup.exe"))
        
        let epicInstaller = manager.installerURL(for: .epic)
        XCTAssertTrue(epicInstaller.path.contains("legendary"))
        XCTAssertTrue(manager.legendaryBinaryURL.path.hasSuffix("engines/legendary/legendary")
            || manager.legendaryBinaryURL.path.contains("/legendary/legendary"))
        XCTAssertTrue(manager.legendaryConfigURL.path.contains("bottles/epic/legendary"))
        
        let gogInstaller = manager.installerURL(for: .gog)
        XCTAssertTrue(gogInstaller.path.contains("setup_galaxy"))
        XCTAssertFalse(gogInstaller.path.hasSuffix("GOG_Galaxy_2.0.exe"))
    }
}
