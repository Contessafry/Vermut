import XCTest
@testable import CaskLauncherCore

final class EngineGraphicsPolicyTests: XCTestCase {
    func testDXVKRequiresStagingOnVermutWine() {
        let inherited = EffectiveSetting(value: WineEngine.grappleWine, source: .global)
        let applied = EngineGraphicsPolicy.apply(inherited: inherited, backend: .dxvk)
        XCTAssertEqual(applied.engine.value, .staging)
        XCTAssertEqual(applied.engine.source, .global)
        XCTAssertTrue(applied.forcedForDXVK)
        XCTAssertTrue(EngineGraphicsPolicy.requiresStaging(for: .dxvk))
    }

    func testDXMTKeepsVermutWine() {
        let inherited = EffectiveSetting(value: WineEngine.grappleWine, source: .bottle)
        let applied = EngineGraphicsPolicy.apply(inherited: inherited, backend: .dxmt)
        XCTAssertEqual(applied.engine.value, .grappleWine)
        XCTAssertFalse(applied.forcedForDXVK)
    }

    func testExplicitStagingUnchanged() {
        let inherited = EffectiveSetting(value: WineEngine.staging, source: .game)
        let applied = EngineGraphicsPolicy.apply(inherited: inherited, backend: .dxvk)
        XCTAssertEqual(applied.engine.value, .staging)
        XCTAssertFalse(applied.forcedForDXVK)
    }

    func testLaunchEngineConvenience() {
        XCTAssertEqual(
            EngineGraphicsPolicy.launchEngine(.grappleWine, backend: .dxvk),
            .staging
        )
        XCTAssertEqual(
            EngineGraphicsPolicy.launchEngine(.devel, backend: .dxvk),
            .devel
        )
    }

    func testPickerLabels() {
        XCTAssertTrue(
            EngineGraphicsPolicy.enginePickerLabel(
                for: .staging,
                effectiveBackend: .dxvk,
                statusSuffix: "Installed"
            ).contains("required by DXVK")
        )
        XCTAssertEqual(
            EngineGraphicsPolicy.graphicsPickerLabel(for: .dxvk),
            "DXVK · Uses Wine Staging"
        )
        XCTAssertEqual(EngineGraphicsPolicy.graphicsPickerLabel(for: .dxmt), "DXMT")
    }

    func testWineManagerPolicyMatchesResolver() {
        // Same inputs → same engine (single source of truth).
        let global = AppConfiguration()
        let bottle = BottleConfiguration(
            engine: SettingInheritance.automatic,
            graphicsBackend: GraphicsBackend.dxvk.rawValue
        )
        let resolved = GameSettingsResolver.resolve(
            game: .automatic,
            bottle: bottle,
            global: global,
            store: .steam
        )
        let viaPolicy = EngineGraphicsPolicy.launchEngine(
            StoreRecipe.effectiveEngine(bottle, global: global).value,
            backend: .dxvk
        )
        XCTAssertEqual(resolved.engine.value, viaPolicy)
        XCTAssertEqual(viaPolicy, .staging)
    }
}
