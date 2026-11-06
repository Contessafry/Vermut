import XCTest
@testable import CaskLauncherCore

final class ComponentCatalogPolicyTests: XCTestCase {
    func testNightlyAndPrereleaseDXMTAreRejected() {
        XCTAssertFalse(
            ComponentCatalog.isOfferedStableRelease(
                tagName: "nightly-2026-10-26",
                prerelease: false,
                draft: false,
                assetNames: ["dxmt-nightly-builtin.tar.gz"]
            )
        )
        XCTAssertFalse(
            ComponentCatalog.isOfferedStableRelease(
                tagName: "v0.81",
                prerelease: true,
                draft: false,
                assetNames: ["dxmt-v0.81-builtin.tar.gz"]
            )
        )
        XCTAssertFalse(
            ComponentCatalog.isOfferedStableRelease(
                tagName: "v0.81",
                prerelease: false,
                draft: true,
                assetNames: ["dxmt-v0.81-builtin.tar.gz"]
            )
        )
        XCTAssertTrue(
            ComponentCatalog.isOfferedStableRelease(
                tagName: "v0.80",
                prerelease: false,
                draft: false,
                assetNames: ["dxmt-v0.80-builtin.tar.gz"]
            )
        )
    }

    func testGcenxArchiveMatcherDoesNotHardcodeVersion() {
        XCTAssertTrue(ComponentCatalog.isGcenxWineArchive("wine-staging-11.20-osx64.tar.xz", engine: .staging))
        XCTAssertTrue(ComponentCatalog.isGcenxWineArchive("wine-devel-11.19-osx64.tar.xz", engine: .devel))
        XCTAssertFalse(ComponentCatalog.isGcenxWineArchive("wine-staging-11.20-osx64.tar.xz", engine: .devel))
        XCTAssertFalse(ComponentCatalog.isGcenxWineArchive("wine-staging-11.20-source.tar.xz", engine: .staging))
    }

    func testSteamOverlayDefaultIsOffOnGameConfiguration() throws {
        let decoded = try JSONDecoder().decode(GameConfiguration.self, from: Data(#"{}"#.utf8))
        XCTAssertFalse(decoded.steamOverlayEnabled)
        XCTAssertFalse(decoded.hasOverrides)

        var enabled = GameConfiguration(steamOverlayEnabled: true)
        XCTAssertTrue(enabled.hasOverrides)
        enabled.resetAll()
        XCTAssertFalse(enabled.steamOverlayEnabled)
    }

    func testGOGRecipePinsSoftwareQt() {
        XCTAssertEqual(GOGRecipe.recommendedEngine, .staging)
        XCTAssertEqual(GOGRecipe.softwareEnvironment["QT_OPENGL"], "software")
        XCTAssertTrue(GOGRecipe.registryWrites().contains {
            if case .add(let write) = $0 {
                return write.value == "renderer" && write.data == "gdi"
            }
            return false
        })
    }
}
