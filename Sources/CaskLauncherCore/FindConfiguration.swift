import Foundation

/// Extra argv appended after Steam `-applaunch <appId>` (or the game exe on other stores).
public struct FindLaunchOption: Hashable, Sendable, Identifiable, Codable {
    public var id: String
    public var arguments: [String]
    public var displayName: String

    public init(id: String, arguments: [String], displayName: String) {
        self.id = id
        self.arguments = arguments
        self.displayName = displayName
    }

    public var argumentString: String {
        arguments.joined(separator: " ")
    }

    public static let none = FindLaunchOption(id: "none", arguments: [], displayName: "None")

    public static let forceGLCore = FindLaunchOption(
        id: "force-glcore",
        arguments: ["-force-glcore"],
        displayName: "-force-glcore"
    )

    /// Unity player: avoid a single-threaded D3D11 device that often fails to init on Wine.
    public static let unityD3D11NoSingleThreaded = FindLaunchOption(
        id: "unity-d3d11-no-st",
        arguments: ["-force-d3d11-no-singlethreaded"],
        displayName: "-force-d3d11-no-singlethreaded"
    )

    /// Small, conservative search set. Order is likelihood (none first).
    public static let searchSet: [FindLaunchOption] = [
        .none,
        .forceGLCore,
        .unityD3D11NoSingleThreaded
    ]

    public static func fromStored(_ raw: String) -> FindLaunchOption {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .none }
        if let match = searchSet.first(where: { $0.argumentString == trimmed || $0.id == trimmed }) {
            return match
        }
        return FindLaunchOption(
            id: "custom",
            arguments: FindLaunchOption.tokenize(trimmed),
            displayName: trimmed
        )
    }

    public static func tokenize(_ raw: String) -> [String] {
        raw.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
    }
}

/// One point in the find-configuration search space.
public struct FindConfigurationCombo: Hashable, Sendable, Identifiable {
    public var engine: WineEngine
    public var graphics: GraphicsBackend
    public var steamOverlayEnabled: Bool
    public var launchOption: FindLaunchOption

    public init(
        engine: WineEngine,
        graphics: GraphicsBackend,
        steamOverlayEnabled: Bool = false,
        launchOption: FindLaunchOption = .none
    ) {
        self.engine = engine
        self.graphics = graphics
        self.steamOverlayEnabled = steamOverlayEnabled
        self.launchOption = launchOption
    }

    public var id: String {
        "\(engine.rawValue)|\(graphics.shortLabel.lowercased())|\(steamOverlayEnabled ? "overlay" : "no-overlay")|\(launchOption.id)"
    }

    public var displayLabel: String {
        var parts = [
            engine.userFacingName,
            graphics.shortLabel
        ]
        if steamOverlayEnabled {
            parts.append("overlay on")
        }
        if !launchOption.arguments.isEmpty {
            parts.append(launchOption.displayName)
        }
        return parts.joined(separator: " · ")
    }

    public var runtimeProfile: BottleRuntimeProfile {
        BottleRuntimeProfile(
            engine: engine,
            graphics: graphics,
            steamOverlayEnabled: steamOverlayEnabled
        )
    }

    /// Persistable per-game overrides for a confirmed working combo.
    public func gameConfiguration(preserving existing: GameConfiguration = .automatic) -> GameConfiguration {
        var config = existing
        config.engine = engine.rawValue
        config.graphicsBackend = graphics.rawValue
        config.steamOverlayEnabled = steamOverlayEnabled
        config.launchOptions = launchOption.argumentString
        return config
    }
}

public enum FindConfigurationSkipReason: String, Sendable, Equatable {
    case engineNotInstalled
    case dxvkRequiresStaging
    case d3dMetalMissing
    case dxmtUnsupportedByEngine
    case storeGraphicsLocked
    case overlayNotApplicable
    case knownNotWorking
}

public struct FindConfigurationContext: Sendable, Equatable {
    public var store: GameStore
    public var installedEngines: Set<WineEngine>
    public var d3dMetalInstalled: Bool
    public var compatibility: GameCompatibility?

    public init(
        store: GameStore,
        installedEngines: Set<WineEngine>,
        d3dMetalInstalled: Bool,
        compatibility: GameCompatibility? = nil
    ) {
        self.store = store
        self.installedEngines = installedEngines
        self.d3dMetalInstalled = d3dMetalInstalled
        self.compatibility = compatibility
    }
}

public struct FindConfigurationSettings: Sendable, Equatable {
    /// How long the game process must stay up (with a real window, no fatal log) before we ask the user.
    public var aliveThreshold: TimeInterval
    /// How often the runner polls process / window / logs.
    public var pollInterval: TimeInterval
    /// Per-attempt Wine log cap (bytes). Store log stays on `CappedLogWriter.defaultMaxBytes`.
    public var attemptLogMaxBytes: UInt64

    public init(
        aliveThreshold: TimeInterval = 45,
        pollInterval: TimeInterval = 2,
        attemptLogMaxBytes: UInt64 = FindConfigurationLog.defaultMaxBytes
    ) {
        self.aliveThreshold = Self.clampThreshold(aliveThreshold)
        self.pollInterval = max(0.5, pollInterval)
        self.attemptLogMaxBytes = max(64 * 1024, attemptLogMaxBytes)
    }

    public static let `default` = FindConfigurationSettings()

    public static let minimumThreshold: TimeInterval = 30
    public static let maximumThreshold: TimeInterval = 60

    public static func clampThreshold(_ value: TimeInterval) -> TimeInterval {
        min(maximumThreshold, max(minimumThreshold, value))
    }
}

/// Builds the pruned, likelihood-ordered search plan.
public enum FindConfigurationPlanner {
    public static func plan(context: FindConfigurationContext) -> [FindConfigurationCombo] {
        var candidates: [FindConfigurationCombo] = []
        let engines = WineEngine.allCases.filter { context.installedEngines.contains($0) }
        let backends = GraphicsBackend.allCases
        let overlays: [Bool] = context.store == .steam ? [false, true] : [false]
        let options = FindLaunchOption.searchSet

        for engine in engines {
            for graphics in backends {
                for overlay in overlays {
                    for option in options {
                        let combo = FindConfigurationCombo(
                            engine: engine,
                            graphics: graphics,
                            steamOverlayEnabled: overlay,
                            launchOption: option
                        )
                        if skipReason(for: combo, context: context) == nil {
                            candidates.append(combo)
                        }
                    }
                }
            }
        }

        return candidates.sorted { lhs, rhs in
            let a = sortKey(lhs, context: context)
            let b = sortKey(rhs, context: context)
            if a != b { return a < b }
            return lhs.id < rhs.id
        }
    }

    public static func skipReason(
        for combo: FindConfigurationCombo,
        context: FindConfigurationContext
    ) -> FindConfigurationSkipReason? {
        if !context.installedEngines.contains(combo.engine) {
            return .engineNotInstalled
        }
        if !StoreRecipe.allowsNativeGraphics(context.store), combo.graphics != .wined3d {
            return .storeGraphicsLocked
        }
        if combo.graphics == .d3dmetal, !context.d3dMetalInstalled {
            return .d3dMetalMissing
        }
        if combo.graphics == .dxvk, !combo.engine.canHostDXVK {
            return .dxvkRequiresStaging
        }
        if combo.graphics == .dxmt, !combo.engine.supportsDXMT {
            return .dxmtUnsupportedByEngine
        }
        if combo.steamOverlayEnabled, context.store != .steam {
            return .overlayNotApplicable
        }
        if matchesKnownNotWorking(combo, context: context) {
            return .knownNotWorking
        }
        return nil
    }

    public static func matchesKnownNotWorking(
        _ combo: FindConfigurationCombo,
        context: FindConfigurationContext
    ) -> Bool {
        guard let banned = context.compatibility?.effectiveKnownNotWorking, !banned.isEmpty else {
            return false
        }
        let graphicsKey = combo.graphics.compatIdentifier
        let engineKeys = combo.engine.compatIdentifiers
        return banned.contains { item in
            guard item.graphics.lowercased() == graphicsKey else { return false }
            guard let engine = item.engine, !engine.isEmpty else { return true }
            return engineKeys.contains(engine.lowercased())
        }
    }

    /// Tuple sort key: lower is more likely.
    public static func sortKey(
        _ combo: FindConfigurationCombo,
        context: FindConfigurationContext
    ) -> (Int, Int, Int, Int, Int, Int) {
        let recommended = context.compatibility?.effectiveRecommended?.lowercased()
        let graphicsKey = combo.graphics.compatIdentifier
        let recommendedRank = (recommended == graphicsKey) ? 0 : 1
        let workingRank = -workingScore(for: graphicsKey, in: context.compatibility)
        let defaultRank = isCommonDefault(combo, store: context.store) ? 0 : 1
        let engineRank = enginePreference(combo.engine)
        let overlayRank = combo.steamOverlayEnabled ? 1 : 0
        let optionRank = optionPreference(combo.launchOption)
        return (recommendedRank, workingRank, defaultRank, engineRank, overlayRank, optionRank)
    }

    public static func workingScore(for graphicsKey: String, in compat: GameCompatibility?) -> Int {
        guard let results = compat?.byGraphics[graphicsKey] else { return 0 }
        return results.perfect * 10 + results.issues * 3
    }

    public static func isCommonDefault(_ combo: FindConfigurationCombo, store: GameStore) -> Bool {
        let expectedGraphics: GraphicsBackend = store == .gog ? .wined3d : .dxmt
        let expectedEngine: WineEngine = store == .gog ? .staging : .grappleWine
        return combo.engine == expectedEngine
            && combo.graphics == expectedGraphics
            && !combo.steamOverlayEnabled
            && combo.launchOption == .none
    }

    public static func enginePreference(_ engine: WineEngine) -> Int {
        switch engine {
        case .grappleWine: return 0
        case .staging: return 1
        case .devel: return 2
        }
    }

    public static func optionPreference(_ option: FindLaunchOption) -> Int {
        FindLaunchOption.searchSet.firstIndex(where: { $0.id == option.id }) ?? FindLaunchOption.searchSet.count
    }
}

public enum FindConfigurationAttemptOutcome: String, Sendable, Equatable {
    case pending
    case skipped
    case failed
    case candidate
    case confirmed
    case rejectedByUser
    case stopped
}

public struct FindConfigurationAttempt: Sendable, Equatable, Identifiable {
    public var index: Int
    public var combo: FindConfigurationCombo
    public var outcome: FindConfigurationAttemptOutcome
    public var detail: String
    public var logURL: URL?

    public var id: String { "\(index)-\(combo.id)" }

    public init(
        index: Int,
        combo: FindConfigurationCombo,
        outcome: FindConfigurationAttemptOutcome = .pending,
        detail: String = "",
        logURL: URL? = nil
    ) {
        self.index = index
        self.combo = combo
        self.outcome = outcome
        self.detail = detail
        self.logURL = logURL
    }
}

extension WineEngine {
    /// DXVK needs a Vulkan loader. Vermut Wine (grapple-wine) does not ship one.
    public var canHostDXVK: Bool {
        self == .staging || self == .devel
    }

    /// Identifiers used in published compat JSON (`vermut-wine` or legacy `grapple-wine`).
    public var compatIdentifiers: Set<String> {
        switch self {
        case .grappleWine: return ["grapple-wine", "vermut-wine"]
        case .staging: return ["staging"]
        case .devel: return ["devel"]
        }
    }

    public var compatIdentifier: String {
        switch self {
        case .grappleWine: return "vermut-wine"
        case .staging: return "staging"
        case .devel: return "devel"
        }
    }
}

extension GraphicsBackend {
    public var compatIdentifier: String {
        switch self {
        case .dxmt: return "dxmt"
        case .dxvk: return "dxvk"
        case .d3dmetal: return "d3dmetal"
        case .wined3d: return "wined3d"
        }
    }
}
