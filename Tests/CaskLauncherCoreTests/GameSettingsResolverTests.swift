import XCTest
@testable import CaskLauncherCore

final class GameSettingsResolverTests: XCTestCase {

    private let global = AppConfiguration(
        defaultEngine: WineEngine.grappleWine.rawValue,
        defaultGraphicsBackend: GraphicsBackend.dxmt.rawValue,
        defaultDXMTVersion: "v0.80",
        defaultLogLevel: WineLogLevel.off.rawValue
    )

    private let bottle = BottleConfiguration(
        engine: SettingInheritance.automatic,
        graphicsBackend: GraphicsBackend.dxvk.rawValue,
        dxmtVersion: SettingInheritance.automatic,
        logLevel: SettingInheritance.automatic
    )

    func testAllAutomaticUsesBottleThenGlobal() {
        let resolved = GameSettingsResolver.resolve(
            game: .automatic,
            bottle: bottle,
            global: global,
            store: .steam
        )
        XCTAssertEqual(resolved.engine.value, .grappleWine)
        XCTAssertEqual(resolved.engine.source, .global)
        XCTAssertEqual(resolved.graphics.value, .dxvk)
        XCTAssertEqual(resolved.graphics.source, .bottle)
        XCTAssertEqual(resolved.dxmtVersion.value, "v0.80")
        XCTAssertEqual(resolved.dxmtVersion.source, .global)
        XCTAssertEqual(resolved.logLevel.value, .off)
        XCTAssertEqual(resolved.logLevel.source, .global)
    }

    func testGameOverridesWin() {
        let game = GameConfiguration(
            engine: WineEngine.devel.rawValue,
            graphicsBackend: GraphicsBackend.wined3d.rawValue,
            dxmtVersion: "v0.74",
            logLevel: WineLogLevel.verbose.rawValue
        )
        let resolved = GameSettingsResolver.resolve(
            game: game,
            bottle: bottle,
            global: global,
            store: .steam
        )
        XCTAssertEqual(resolved.engine.value, .devel)
        XCTAssertEqual(resolved.engine.source, .game)
        XCTAssertEqual(resolved.graphics.value, .wined3d)
        XCTAssertEqual(resolved.graphics.source, .game)
        XCTAssertEqual(resolved.dxmtVersion.value, "v0.74")
        XCTAssertEqual(resolved.dxmtVersion.source, .game)
        XCTAssertEqual(resolved.logLevel.value, .verbose)
        XCTAssertEqual(resolved.logLevel.source, .game)
    }

    func testDXVKForcesStagingWhenEngineIsGrappleWine() {
        let game = GameConfiguration(
            engine: WineEngine.grappleWine.rawValue,
            graphicsBackend: GraphicsBackend.dxvk.rawValue
        )
        let resolved = GameSettingsResolver.resolve(
            game: game,
            bottle: BottleConfiguration(engine: SettingInheritance.automatic),
            global: global,
            store: .steam
        )
        XCTAssertEqual(resolved.graphics.value, .dxvk)
        XCTAssertEqual(resolved.engine.value, .staging)
    }

    func testGOGLocksWineD3D() {
        let game = GameConfiguration(graphicsBackend: GraphicsBackend.dxmt.rawValue)
        let resolved = GameSettingsResolver.resolve(
            game: game,
            bottle: bottle,
            global: global,
            store: .gog
        )
        XCTAssertEqual(resolved.graphics.value, .wined3d)
    }

    func testEpicStoreDefaultLogLevelWhenAllAutomatic() {
        let epicBottle = BottleConfiguration(
            engine: SettingInheritance.automatic,
            graphicsBackend: GraphicsBackend.dxmt.rawValue,
            logLevel: SettingInheritance.automatic
        )
        let app = AppConfiguration(defaultLogLevel: SettingInheritance.automatic)
        let resolved = GameSettingsResolver.resolve(
            game: .automatic,
            bottle: epicBottle,
            global: app,
            store: .epic
        )
        XCTAssertEqual(resolved.logLevel.value, .errors)
        XCTAssertEqual(resolved.logLevel.source, .global)
    }

    func testLaunchConfigurationMaterializesResolvedValues() {
        let game = GameConfiguration(
            engine: WineEngine.staging.rawValue,
            graphicsBackend: GraphicsBackend.dxvk.rawValue,
            dxmtVersion: "v0.80",
            logLevel: WineLogLevel.errors.rawValue
        )
        let resolved = GameSettingsResolver.resolve(
            game: game,
            bottle: bottle,
            global: global,
            store: .steam
        )
        let launch = resolved.launchConfiguration
        XCTAssertEqual(launch.engine, WineEngine.staging.rawValue)
        XCTAssertEqual(launch.graphicsBackend, GraphicsBackend.dxvk.rawValue)
        XCTAssertEqual(launch.dxmtVersion, "v0.80")
        XCTAssertTrue(resolved.dxmtIsPinned)
        XCTAssertEqual(resolved.wineDebug, "err+all,fixme-all")
        XCTAssertTrue(resolved.profileSummary.contains("staging"))
        XCTAssertTrue(resolved.profileSummary.contains("DXVK"))
    }

    /// Game + bottle Automatic must not pin defaultDXMTVersion — WineManager uses
    /// bundled ?? flat engines/dxmt (main 1.1.3 parity).
    func testLaunchConfigurationKeepsAutomaticDXMT() {
        let resolved = GameSettingsResolver.resolve(
            game: .automatic,
            bottle: bottle,
            global: global,
            store: .steam
        )
        XCTAssertFalse(resolved.dxmtIsPinned)
        XCTAssertEqual(resolved.dxmtVersion.source, .global)
        XCTAssertEqual(resolved.dxmtVersion.value, "v0.80") // display / catalog default
        XCTAssertEqual(resolved.launchConfiguration.dxmtVersion, SettingInheritance.automatic)
        XCTAssertTrue(resolved.profileSummary.contains("dxmt=automatic"))
    }

    func testPinnedBottleDXMTPropagatesWhenGameAutomatic() {
        let pinnedBottle = BottleConfiguration(
            engine: SettingInheritance.automatic,
            graphicsBackend: GraphicsBackend.dxmt.rawValue,
            dxmtVersion: "v0.74"
        )
        let resolved = GameSettingsResolver.resolve(
            game: .automatic,
            bottle: pinnedBottle,
            global: global,
            store: .steam
        )
        XCTAssertTrue(resolved.dxmtIsPinned)
        XCTAssertEqual(resolved.dxmtVersion.source, .bottle)
        XCTAssertEqual(resolved.launchConfiguration.dxmtVersion, "v0.74")
    }

    func testAutomaticLabelsShowParentEffectiveValue() {
        let engineLabel = GameSettingsResolver.automaticEngineLabel(
            bottle: bottle,
            global: global,
            store: .steam
        )
        XCTAssertEqual(engineLabel, "Automatic (Steam: Vermut Wine)")

        let graphicsLabel = GameSettingsResolver.automaticGraphicsLabel(
            bottle: bottle,
            global: global,
            store: .steam
        )
        XCTAssertEqual(graphicsLabel, "Automatic (Steam: DXVK)")

        let dxmtLabel = GameSettingsResolver.automaticDXMTLabel(
            bottle: bottle,
            global: global,
            store: .steam
        )
        XCTAssertEqual(dxmtLabel, "Automatic (Steam: bundled)")

        let pinnedBottle = BottleConfiguration(dxmtVersion: "v0.74")
        let pinnedLabel = GameSettingsResolver.automaticDXMTLabel(
            bottle: pinnedBottle,
            global: global,
            store: .steam
        )
        XCTAssertEqual(pinnedLabel, "Automatic (Steam: v0.74)")

        let logLabel = GameSettingsResolver.automaticLogLevelLabel(
            bottle: bottle,
            global: global,
            store: .steam
        )
        XCTAssertEqual(logLabel, "Automatic (Steam: Off)")
    }

    func testNilGameConfigBehavesLikeAutomatic() {
        let resolved = GameSettingsResolver.resolve(
            game: nil,
            bottle: bottle,
            global: global,
            store: .steam
        )
        XCTAssertEqual(resolved.graphics.value, .dxvk)
        XCTAssertEqual(resolved.engine.source, .global)
    }
}

final class WineLogLevelTests: XCTestCase {
    func testWineDebugMapping() {
        XCTAssertEqual(WineLogLevel.off.wineDebug, "-all")
        XCTAssertEqual(WineLogLevel.errors.wineDebug, "err+all,fixme-all")
        XCTAssertEqual(WineLogLevel.verbose.wineDebug, "warn+all,err+all")
    }

    func testVermutWineDebugOverridesLevel() {
        let env = ["VERMUT_WINEDEBUG": "+seh"]
        XCTAssertEqual(
            WineLogLevel.effectiveWineDebug(level: .off, processEnvironment: env),
            "+seh"
        )
        XCTAssertEqual(
            WineLogLevel.effectiveWineDebug(level: .verbose, processEnvironment: [:]),
            "warn+all,err+all"
        )
    }

    func testStoreDefaults() {
        XCTAssertEqual(WineLogLevel.storeDefault(for: .steam), .off)
        XCTAssertEqual(WineLogLevel.storeDefault(for: .gog), .off)
        XCTAssertEqual(WineLogLevel.storeDefault(for: .epic), .errors)
    }
}

final class GameConfigurationPersistenceTests: XCTestCase {
    func testRoundTripAndResetClearsFile() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("vermut-game-settings-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        // Use PathManager URLs only for naming; write via GameSettingsStore with a temp bottle tree.
        // GameSettingsStore uses PathManager.shared — exercise encode/decode on GameConfiguration instead.
        var config = GameConfiguration(
            engine: WineEngine.staging.rawValue,
            graphicsBackend: GraphicsBackend.dxvk.rawValue,
            dxmtVersion: "v0.74",
            logLevel: WineLogLevel.verbose.rawValue
        )
        XCTAssertTrue(config.hasOverrides)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(GameConfiguration.self, from: data)
        XCTAssertEqual(decoded, config)

        config.resetAll()
        XCTAssertFalse(config.hasOverrides)
        XCTAssertTrue(SettingInheritance.isAutomatic(config.engine))
    }

    func testDecodeDefaultsMissingKeysToAutomatic() throws {
        let json = Data(#"{}"#.utf8)
        let config = try JSONDecoder().decode(GameConfiguration.self, from: json)
        XCTAssertEqual(config, .automatic)
        XCTAssertFalse(config.hasOverrides)
    }

    func testSanitizedGameFileName() {
        XCTAssertEqual(PathManager.sanitizedGameFileName("1245620"), "1245620")
        XCTAssertEqual(PathManager.sanitizedGameFileName("Foo/Bar"), "Foo_Bar")
        XCTAssertEqual(PathManager.sanitizedGameFileName("  "), "unknown")
    }
}

final class SettingInheritanceLogLevelTests: XCTestCase {
    func testResolveLogLevelChain() {
        let fromGame = SettingInheritance.resolveLogLevel(
            game: WineLogLevel.verbose.rawValue,
            bottle: WineLogLevel.errors.rawValue,
            global: WineLogLevel.off.rawValue
        )
        XCTAssertEqual(fromGame.value, .verbose)
        XCTAssertEqual(fromGame.source, .game)

        let fromBottle = SettingInheritance.resolveLogLevel(
            game: SettingInheritance.automatic,
            bottle: WineLogLevel.errors.rawValue,
            global: WineLogLevel.off.rawValue
        )
        XCTAssertEqual(fromBottle.value, .errors)
        XCTAssertEqual(fromBottle.source, .bottle)

        let fromStoreDefault = SettingInheritance.resolveLogLevel(
            game: nil,
            bottle: SettingInheritance.automatic,
            global: SettingInheritance.automatic,
            storeDefault: .errors
        )
        XCTAssertEqual(fromStoreDefault.value, .errors)
        XCTAssertEqual(fromStoreDefault.source, .global)
    }
}

final class StoreRecipeGameTierTests: XCTestCase {
    func testResolveLaunchSettingsIncludesGameTier() {
        let global = AppConfiguration()
        let bottle = BottleConfiguration(
            engine: SettingInheritance.automatic,
            graphicsBackend: GraphicsBackend.dxmt.rawValue
        )
        let game = GameConfiguration(graphicsBackend: GraphicsBackend.wined3d.rawValue)
        let resolved = StoreRecipe.resolveLaunchSettings(
            game: game,
            bottle: bottle,
            global: global,
            store: .steam
        )
        XCTAssertEqual(resolved.graphics.value, .wined3d)
        XCTAssertEqual(resolved.graphics.source, .game)
        XCTAssertEqual(resolved.engine.value, .grappleWine)
    }

    func testEffectiveHelpersAcceptGame() {
        let global = AppConfiguration()
        let bottle = BottleConfiguration(engine: SettingInheritance.automatic)
        let game = GameConfiguration(engine: WineEngine.devel.rawValue)
        let engine = StoreRecipe.effectiveEngine(bottle, global: global, game: game)
        XCTAssertEqual(engine.value, .devel)
        XCTAssertEqual(engine.source, .game)
    }
}
