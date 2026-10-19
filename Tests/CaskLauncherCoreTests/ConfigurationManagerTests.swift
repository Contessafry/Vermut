import XCTest
@testable import CaskLauncherCore

final class ConfigurationManagerTests: XCTestCase {
    
    var tempConfigURL: URL!
    
    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempConfigURL = tempDir.appendingPathComponent("test-config-\(UUID().uuidString).json")
    }
    
    override func tearDown() {
        if let url = tempConfigURL {
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    func testDefaultConfiguration() throws {
        let manager = ConfigurationManager.shared
        let config = try manager.loadConfiguration()
        
        XCTAssertEqual(config.defaultGraphicsBackend, GraphicsBackend.dxmt.rawValue)
        XCTAssertEqual(AppConfiguration().defaultEngine, WineEngine.grappleWine.rawValue)
        XCTAssertTrue(config.enableHiDPI)
        XCTAssertEqual(config.windowsVersion, "win10")
    }
    
    func testConfigurationCodable() throws {
        let config = AppConfiguration(
            defaultEngine: WineEngine.staging.rawValue,
            defaultGraphicsBackend: GraphicsBackend.d3dmetal.rawValue,
            enableHiDPI: false,
            windowsVersion: "win7"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        
        let decoder = JSONDecoder()
        let decodedConfig = try decoder.decode(AppConfiguration.self, from: data)
        
        XCTAssertEqual(decodedConfig.defaultEngine, config.defaultEngine)
        XCTAssertEqual(decodedConfig.defaultGraphicsBackend, config.defaultGraphicsBackend)
        XCTAssertEqual(decodedConfig.enableHiDPI, config.enableHiDPI)
        XCTAssertEqual(decodedConfig.windowsVersion, config.windowsVersion)
    }
}
