import XCTest
@testable import CaskLauncherCore

final class WineEngineVersionTests: XCTestCase {
    var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-engine-ver-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        super.tearDown()
    }

    func testParseVersionToken() {
        XCTAssertEqual(WineEngineVersion.parseVersionToken("11.18"), "11.18")
        XCTAssertEqual(WineEngineVersion.parseVersionToken("  v11.20  "), "11.20")
        XCTAssertEqual(WineEngineVersion.parseVersionToken("Wine Staging 11.19"), "11.19")
        XCTAssertEqual(WineEngineVersion.parseVersionToken("11.18 (1)"), "11.18")
        XCTAssertNil(WineEngineVersion.parseVersionToken("   "))
        XCTAssertNil(WineEngineVersion.parseVersionToken("Wine Staging"))
    }

    func testRecordedVersionRoundTrip() throws {
        try WineEngineVersion.writeRecorded("11.20", toEngineRoot: tempRoot)
        XCTAssertEqual(WineEngineVersion.readRecorded(fromEngineRoot: tempRoot), "11.20")
        XCTAssertEqual(WineEngineVersion.resolved(fromEngineRoot: tempRoot), "11.20")
    }

    func testProbeReadsGcenxInfoPlistWhenNoRecordedVersion() throws {
        try writeGcenxPlist(version: "11.19")
        XCTAssertNil(WineEngineVersion.readRecorded(fromEngineRoot: tempRoot))
        XCTAssertEqual(WineEngineVersion.probeBundleVersion(fromEngineRoot: tempRoot), "11.19")
        XCTAssertEqual(
            WineEngineVersion.resolved(fromEngineRoot: tempRoot, persistProbe: true),
            "11.19"
        )
        XCTAssertEqual(WineEngineVersion.readRecorded(fromEngineRoot: tempRoot), "11.19")
    }

    func testDisplayVersionDoesNotInventInstalledTag() {
        XCTAssertEqual(
            WineEngineVersion.displayVersion(
                isInstalled: true,
                installedVersion: "11.18",
                catalogVersion: "11.20",
                fallbackVersion: "11.18"
            ),
            "11.18"
        )
        XCTAssertNil(
            WineEngineVersion.displayVersion(
                isInstalled: true,
                installedVersion: nil,
                catalogVersion: "11.20",
                fallbackVersion: "11.18"
            )
        )
        XCTAssertEqual(
            WineEngineVersion.displayVersion(
                isInstalled: false,
                installedVersion: nil,
                catalogVersion: "11.20",
                fallbackVersion: "11.18"
            ),
            "11.20"
        )
        XCTAssertEqual(
            WineEngineVersion.displayVersion(
                isInstalled: false,
                installedVersion: nil,
                catalogVersion: nil,
                fallbackVersion: "11.18"
            ),
            "11.18"
        )
    }

    func testUpdateAvailableComparesCatalogToInstalled() {
        XCTAssertTrue(
            WineEngineVersion.isUpdateAvailable(
                engine: .staging,
                isInstalled: true,
                installedVersion: "11.18",
                catalogVersion: "11.20"
            )
        )
        XCTAssertFalse(
            WineEngineVersion.isUpdateAvailable(
                engine: .staging,
                isInstalled: true,
                installedVersion: "11.20",
                catalogVersion: "11.20"
            )
        )
        XCTAssertFalse(
            WineEngineVersion.isUpdateAvailable(
                engine: .staging,
                isInstalled: true,
                installedVersion: "11.20",
                catalogVersion: "11.18"
            )
        )
        XCTAssertFalse(
            WineEngineVersion.isUpdateAvailable(
                engine: .staging,
                isInstalled: false,
                installedVersion: nil,
                catalogVersion: "11.20"
            )
        )
    }

    func testUnknownInstalledVersionOffersUpdate() {
        XCTAssertTrue(
            WineEngineVersion.isUpdateAvailable(
                engine: .devel,
                isInstalled: true,
                installedVersion: nil,
                catalogVersion: "11.20"
            )
        )
        XCTAssertFalse(
            WineEngineVersion.isUpdateAvailable(
                engine: .devel,
                isInstalled: true,
                installedVersion: nil,
                catalogVersion: nil
            )
        )
    }

    func testGrappleWineIsNeverOfferedAnUpdate() {
        XCTAssertFalse(
            WineEngineVersion.isUpdateAvailable(
                engine: .grappleWine,
                isInstalled: true,
                installedVersion: "1.0.2",
                catalogVersion: "1.0.3"
            )
        )
    }

    func testCannotApplyUpdateWhileInUseOrBusy() {
        XCTAssertTrue(WineEngineVersion.canApplyUpdate(isInUse: false, isBusy: false))
        XCTAssertFalse(WineEngineVersion.canApplyUpdate(isInUse: true, isBusy: false))
        XCTAssertFalse(WineEngineVersion.canApplyUpdate(isInUse: false, isBusy: true))
    }

    func testUsageHelper() {
        XCTAssertTrue(
            WineEngineUsage.isInUse(
                .staging,
                runningStoreEngines: [.staging],
                runningCustomEngines: []
            )
        )
        XCTAssertTrue(
            WineEngineUsage.isInUse(
                .devel,
                runningStoreEngines: [],
                runningCustomEngines: [.devel]
            )
        )
        XCTAssertFalse(
            WineEngineUsage.isInUse(
                .staging,
                runningStoreEngines: [.grappleWine],
                runningCustomEngines: [.devel]
            )
        )
    }

    private func writeGcenxPlist(version: String) throws {
        let app = tempRoot.appendingPathComponent("Wine Staging.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleShortVersionString</key>
            <string>\(version)</string>
            <key>CFBundleVersion</key>
            <string>\(version)</string>
        </dict>
        </plist>
        """
        try Data(plist.utf8).write(to: app.appendingPathComponent("Info.plist"))
    }
}
