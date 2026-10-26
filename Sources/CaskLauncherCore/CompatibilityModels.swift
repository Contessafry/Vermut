import Foundation

public struct CompatibilityReport: Codable, Sendable {
    public let store: String
    public let gameId: String
    public let gameName: String?
    public let vermutVersion: String
    public let engine: String
    public let graphics: String
    public let macOS: String
    public let chip: String
    public let playMinutes: Int
    public let result: String
    public let autoDetectedCrash: Bool?
    public let note: String?
    
    public init(
        store: String,
        gameId: String,
        gameName: String?,
        vermutVersion: String,
        engine: String,
        graphics: String,
        macOS: String,
        chip: String,
        playMinutes: Int,
        result: String,
        autoDetectedCrash: Bool? = nil,
        note: String? = nil
    ) {
        self.store = store
        self.gameId = gameId
        self.gameName = gameName
        self.vermutVersion = vermutVersion
        self.engine = engine
        self.graphics = graphics
        self.macOS = macOS
        self.chip = chip
        self.playMinutes = playMinutes
        self.result = result
        self.autoDetectedCrash = autoDetectedCrash
        self.note = note
    }
}

/// A backend + engine pair that only has broken community reports.
public struct KnownNotWorkingCombo: Codable, Sendable, Equatable, Identifiable {
    public let graphics: String
    public let engine: String?

    public var id: String { "\(graphics)/\(engine ?? "unknown")" }

    public init(graphics: String, engine: String? = nil) {
        self.graphics = graphics
        self.engine = engine
    }

    public var displayLabel: String {
        let backend = Self.graphicsName(graphics)
        guard let engine, !engine.isEmpty else { return backend }
        return "\(backend) (\(Self.engineName(engine)))"
    }

    public static func graphicsName(_ identifier: String) -> String {
        switch identifier.lowercased() {
        case "dxmt": return "DXMT"
        case "dxvk": return "DXVK"
        case "d3dmetal": return "D3DMetal"
        case "wined3d": return "WineD3D"
        default: return identifier.uppercased()
        }
    }

    public static func engineName(_ identifier: String) -> String {
        switch identifier.lowercased() {
        case "grapple-wine", "vermut-wine": return "Vermut Wine"
        case "staging": return "Wine Staging"
        case "devel": return "Wine Devel"
        default: return identifier
        }
    }
}

public struct GameCompatibility: Codable, Sendable, Equatable {
    public let store: String
    public let gameId: String
    public let gameName: String?
    public let byGraphics: [String: GraphicsResults]
    public let recommended: String?
    public let knownNotWorking: [KnownNotWorkingCombo]
    public let totalReports: Int
    
    public struct GraphicsResults: Codable, Sendable, Equatable {
        public let perfect: Int
        public let issues: Int
        public let broken: Int
        
        public var total: Int { perfect + issues + broken }

        public var hasWorkingReports: Bool { perfect + issues > 0 }
    }

    public init(
        store: String,
        gameId: String,
        gameName: String?,
        byGraphics: [String: GraphicsResults],
        recommended: String?,
        totalReports: Int,
        knownNotWorking: [KnownNotWorkingCombo] = []
    ) {
        self.store = store
        self.gameId = gameId
        self.gameName = gameName
        self.byGraphics = byGraphics
        self.recommended = recommended
        self.knownNotWorking = knownNotWorking
        self.totalReports = totalReports
    }

    enum CodingKeys: String, CodingKey {
        case store, gameId, gameName, byGraphics, recommended, knownNotWorking, totalReports
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        store = try container.decode(String.self, forKey: .store)
        gameId = try container.decode(String.self, forKey: .gameId)
        gameName = try container.decodeIfPresent(String.self, forKey: .gameName)
        byGraphics = try container.decodeIfPresent([String: GraphicsResults].self, forKey: .byGraphics) ?? [:]
        recommended = try container.decodeIfPresent(String.self, forKey: .recommended)
        knownNotWorking = try container.decodeIfPresent([KnownNotWorkingCombo].self, forKey: .knownNotWorking) ?? []
        totalReports = try container.decodeIfPresent(Int.self, forKey: .totalReports) ?? 0
    }
    
    public var workingReports: Int {
        byGraphics.values.reduce(0) { $0 + $1.perfect }
    }
    
    public var issuesReports: Int {
        byGraphics.values.reduce(0) { $0 + $1.issues }
    }
    
    public var brokenReports: Int {
        byGraphics.values.reduce(0) { $0 + $1.broken }
    }

    /// Recommendation only when that backend has at least one working report.
    /// Older `compat-data` JSON may still mark a backend that is broken-only.
    public var effectiveRecommended: String? {
        guard let recommended else { return nil }
        if let results = byGraphics[recommended], !results.hasWorkingReports {
            return nil
        }
        let anyWorking = byGraphics.values.contains(where: \.hasWorkingReports)
        return anyWorking ? recommended : nil
    }

    /// Published `knownNotWorking`, or a fallback derived from broken-only backends.
    public var effectiveKnownNotWorking: [KnownNotWorkingCombo] {
        if !knownNotWorking.isEmpty { return knownNotWorking }
        return byGraphics.compactMap { key, value in
            guard !value.hasWorkingReports, value.broken > 0 else { return nil }
            return KnownNotWorkingCombo(graphics: key, engine: nil)
        }
        .sorted { $0.displayLabel < $1.displayLabel }
    }
}

public struct CompatibilityData: Codable, Sendable {
    public let games: [GameCompatibility]
    public let generated: Int
}

public enum CompatibilityResult: String, CaseIterable, Sendable {
    case perfect
    case issues
    case broken
    
    public var displayName: String {
        switch self {
        case .perfect: return "Works perfectly"
        case .issues: return "Minor issues"
        case .broken: return "Doesn't work"
        }
    }
}

public struct GameSession: Sendable, Equatable {
    public let store: GameStore
    public let gameId: String
    public let gameName: String?
    public let engine: String
    public let graphics: String
    public let startTime: Date
    
    public init(store: GameStore, gameId: String, gameName: String?, engine: String, graphics: String, startTime: Date) {
        self.store = store
        self.gameId = gameId
        self.gameName = gameName
        self.engine = engine
        self.graphics = graphics
        self.startTime = startTime
    }
    
    public var playMinutes: Int {
        Int(Date().timeIntervalSince(startTime) / 60)
    }
}
