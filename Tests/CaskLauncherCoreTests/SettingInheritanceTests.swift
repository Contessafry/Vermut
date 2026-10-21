import XCTest
@testable import CaskLauncherCore

final class SettingInheritanceTests: XCTestCase {
    func testAutomaticSentinel() {
        XCTAssertTrue(SettingInheritance.isAutomatic(nil))
        XCTAssertTrue(SettingInheritance.isAutomatic(""))
        XCTAssertTrue(SettingInheritance.isAutomatic("automatic"))
        XCTAssertFalse(SettingInheritance.isAutomatic("staging"))
    }

    func testResolveEngineChain() {
        let fromGame = SettingInheritance.resolveEngine(
            game: "devel",
            bottle: "staging",
            global: "grapple-wine"
        )
        XCTAssertEqual(fromGame.value, .devel)
        XCTAssertEqual(fromGame.source, .game)

        let fromBottle = SettingInheritance.resolveEngine(
            game: "automatic",
            bottle: "staging",
            global: "grapple-wine"
        )
        XCTAssertEqual(fromBottle.value, .staging)
        XCTAssertEqual(fromBottle.source, .bottle)

        let fromGlobal = SettingInheritance.resolveEngine(
            game: nil,
            bottle: "automatic",
            global: "grapple-wine"
        )
        XCTAssertEqual(fromGlobal.value, .grappleWine)
        XCTAssertEqual(fromGlobal.source, .global)
    }

    func testAutomaticLabel() {
        let label = SettingInheritance.automaticLabel(scope: "default", effectiveDisplay: "Vermut Wine")
        XCTAssertEqual(label, "Automatic (default: Vermut Wine)")
    }

    func testResolveDXMTVersion() {
        let effective = SettingInheritance.resolveDXMTVersion(
            game: nil,
            bottle: "automatic",
            global: "v0.80"
        )
        XCTAssertEqual(effective.value, "v0.80")
        XCTAssertEqual(effective.source, .global)
    }
}
