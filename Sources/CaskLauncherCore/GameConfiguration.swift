import Foundation

/// Per-game overrides. Each field is `SettingInheritance.automatic` or an explicit raw value.
/// Inheritance: Settings (global) → bottle/store → game.
public struct GameConfiguration: Codable, Sendable, Equatable {
    /// `SettingInheritance.automatic` or a `WineEngine.rawValue`.
    public var engine: String
    /// `SettingInheritance.automatic` or a `GraphicsBackend.rawValue`.
    public var graphicsBackend: String
    /// `SettingInheritance.automatic` or a DXMT tag such as `v0.80`.
    public var dxmtVersion: String
    /// `SettingInheritance.automatic` or a `WineLogLevel.rawValue`.
    public var logLevel: String

    public init(
        engine: String = SettingInheritance.automatic,
        graphicsBackend: String = SettingInheritance.automatic,
        dxmtVersion: String = SettingInheritance.automatic,
        logLevel: String = SettingInheritance.automatic
    ) {
        self.engine = engine
        self.graphicsBackend = graphicsBackend
        self.dxmtVersion = dxmtVersion
        self.logLevel = logLevel
    }

    enum CodingKeys: String, CodingKey {
        case engine, graphicsBackend, dxmtVersion, logLevel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engine = try container.decodeIfPresent(String.self, forKey: .engine)
            ?? SettingInheritance.automatic
        graphicsBackend = try container.decodeIfPresent(String.self, forKey: .graphicsBackend)
            ?? SettingInheritance.automatic
        dxmtVersion = try container.decodeIfPresent(String.self, forKey: .dxmtVersion)
            ?? SettingInheritance.automatic
        logLevel = try container.decodeIfPresent(String.self, forKey: .logLevel)
            ?? SettingInheritance.automatic
    }

    public var hasOverrides: Bool {
        !SettingInheritance.isAutomatic(engine)
            || !SettingInheritance.isAutomatic(graphicsBackend)
            || !SettingInheritance.isAutomatic(dxmtVersion)
            || !SettingInheritance.isAutomatic(logLevel)
    }

    public mutating func resetAll() {
        engine = SettingInheritance.automatic
        graphicsBackend = SettingInheritance.automatic
        dxmtVersion = SettingInheritance.automatic
        logLevel = SettingInheritance.automatic
    }

    public static let automatic = GameConfiguration()
}

/// Effective engine / graphics / DXMT / log level for one game launch, plus a
/// materialized `BottleConfiguration` with explicit values for WineManager.
public struct ResolvedLaunchSettings: Equatable, Sendable {
    public var engine: EffectiveSetting<WineEngine>
    public var graphics: EffectiveSetting<GraphicsBackend>
    public var dxmtVersion: EffectiveSetting<String>
    public var logLevel: EffectiveSetting<WineLogLevel>
    /// Bottle fields for this launch (HiDPI / Windows version from the bottle).
    public var bottleBase: BottleConfiguration
    /// True when Staging was selected because DXVK cannot run on Vermut Wine.
    public var engineForcedForDXVK: Bool

    public init(
        engine: EffectiveSetting<WineEngine>,
        graphics: EffectiveSetting<GraphicsBackend>,
        dxmtVersion: EffectiveSetting<String>,
        logLevel: EffectiveSetting<WineLogLevel>,
        bottleBase: BottleConfiguration,
        engineForcedForDXVK: Bool = false
    ) {
        self.engine = engine
        self.graphics = graphics
        self.dxmtVersion = dxmtVersion
        self.logLevel = logLevel
        self.bottleBase = bottleBase
        self.engineForcedForDXVK = engineForcedForDXVK
    }

    /// Whether DXMT was explicitly pinned on the game or bottle (not Automatic inherit).
    /// When false, launch keeps `dxmtVersion = automatic` so WineManager uses
    /// bundled ?? flat `engines/dxmt` — same as main 1.1.3.
    public var dxmtIsPinned: Bool {
        dxmtVersion.source == .game || dxmtVersion.source == .bottle
    }

    /// Config with resolved engine / graphics for this launch.
    /// DXMT stays Automatic unless game or bottle pinned a version.
    public var launchConfiguration: BottleConfiguration {
        var config = bottleBase
        config.engine = engine.value.rawValue
        config.graphicsBackend = graphics.value.rawValue
        if dxmtIsPinned {
            config.dxmtVersion = dxmtVersion.value
        } else {
            config.dxmtVersion = SettingInheritance.automatic
        }
        return config
    }

    public var wineDebug: String {
        logLevel.value.wineDebug
    }

    /// Compact profile string for compat reports / session tracking.
    public var profileSummary: String {
        let dxmtPart = dxmtIsPinned ? dxmtVersion.value : "automatic"
        let forced = engineForcedForDXVK ? ";dxvk→staging" : ""
        return "engine=\(engine.value.rawValue);graphics=\(graphics.value.shortLabel);dxmt=\(dxmtPart);log=\(logLevel.value.rawValue)\(forced)"
    }

    /// Staging must be on disk before a DXVK launch that forced it.
    public var requiresStagingInstall: Bool {
        engineForcedForDXVK || (graphics.value == .dxvk && engine.value == .staging)
    }
}

/// Resolves Settings → bottle → game into concrete launch settings.
public enum GameSettingsResolver {
    public static func resolve(
        game: GameConfiguration?,
        bottle: BottleConfiguration,
        global: AppConfiguration,
        store: GameStore
    ) -> ResolvedLaunchSettings {
        let gameConfig = game ?? .automatic

        let engine = SettingInheritance.resolveEngine(
            game: gameConfig.engine,
            bottle: bottle.engine,
            global: global.defaultEngine
        )

        let graphics = SettingInheritance.resolveGraphics(
            game: gameConfig.graphicsBackend,
            bottle: bottle.graphicsBackend,
            global: global.defaultGraphicsBackend
        )

        let dxmt = SettingInheritance.resolveDXMTVersion(
            game: gameConfig.dxmtVersion,
            bottle: bottle.dxmtVersion,
            global: global.defaultDXMTVersion
        )

        let logLevel = SettingInheritance.resolveLogLevel(
            game: gameConfig.logLevel,
            bottle: bottle.logLevel,
            global: global.defaultLogLevel,
            storeDefault: WineLogLevel.storeDefault(for: store)
        )

        var graphicsValue = graphics
        if store == .gog {
            graphicsValue = EffectiveSetting(value: .wined3d, source: graphics.source)
        }

        let applied = EngineGraphicsPolicy.apply(inherited: engine, backend: graphicsValue.value)
        return ResolvedLaunchSettings(
            engine: applied.engine,
            graphics: graphicsValue,
            dxmtVersion: dxmt,
            logLevel: logLevel,
            bottleBase: bottle,
            engineForcedForDXVK: applied.forcedForDXVK
        )
    }

    /// Parent-scope Automatic label for a game picker (bottle effective value).
    /// When `effectiveGraphics` is DXVK and the parent engine is Vermut Wine, shows Staging
    /// (required by DXVK) so the inspector matches launch.
    public static func automaticEngineLabel(
        bottle: BottleConfiguration,
        global: AppConfiguration,
        store: GameStore,
        effectiveGraphics: GraphicsBackend? = nil
    ) -> String {
        let parent = SettingInheritance.resolveEngine(
            bottle: bottle.engine,
            global: global.defaultEngine
        )
        let backend = effectiveGraphics
            ?? SettingInheritance.resolveGraphics(
                bottle: bottle.graphicsBackend,
                global: global.defaultGraphicsBackend
            ).value
        let applied = EngineGraphicsPolicy.apply(inherited: parent, backend: backend)
        let display = applied.forcedForDXVK
            ? EngineGraphicsPolicy.stagingRequiredByDXVKLabel
            : applied.engine.value.userFacingName
        return SettingInheritance.automaticLabel(
            scope: store.shortNameForInheritance,
            effectiveDisplay: display
        )
    }

    public static func automaticGraphicsLabel(
        bottle: BottleConfiguration,
        global: AppConfiguration,
        store: GameStore
    ) -> String {
        let parent = SettingInheritance.resolveGraphics(
            bottle: bottle.graphicsBackend,
            global: global.defaultGraphicsBackend
        )
        let value = store == .gog ? GraphicsBackend.wined3d : parent.value
        return SettingInheritance.automaticLabel(
            scope: store.shortNameForInheritance,
            effectiveDisplay: value.shortLabel
        )
    }

    public static func automaticDXMTLabel(
        bottle: BottleConfiguration,
        global: AppConfiguration,
        store: GameStore
    ) -> String {
        // Bottle Automatic → main parity (bundled / flat engines/dxmt), not a pinned catalog tag.
        if SettingInheritance.isAutomatic(bottle.dxmtVersion) {
            return SettingInheritance.automaticLabel(
                scope: store.shortNameForInheritance,
                effectiveDisplay: "bundled"
            )
        }
        let parent = SettingInheritance.resolveDXMTVersion(
            bottle: bottle.dxmtVersion,
            global: global.defaultDXMTVersion
        )
        return SettingInheritance.automaticLabel(
            scope: store.shortNameForInheritance,
            effectiveDisplay: parent.value
        )
    }

    public static func automaticLogLevelLabel(
        bottle: BottleConfiguration,
        global: AppConfiguration,
        store: GameStore
    ) -> String {
        let parent = SettingInheritance.resolveLogLevel(
            bottle: bottle.logLevel,
            global: global.defaultLogLevel,
            storeDefault: WineLogLevel.storeDefault(for: store)
        )
        return SettingInheritance.automaticLabel(
            scope: store.shortNameForInheritance,
            effectiveDisplay: parent.value.displayName
        )
    }
}

extension GameStore {
    /// Short name used in Automatic picker labels (`Steam`, `Epic`, `GOG`).
    public var shortNameForInheritance: String {
        switch self {
        case .steam: return "Steam"
        case .epic: return "Epic"
        case .gog: return "GOG"
        }
    }
}
