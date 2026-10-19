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

public struct GameCompatibility: Codable, Sendable, Equatable {
    public let store: String
    public let gameId: String
    public let gameName: String?
    public let byGraphics: [String: GraphicsResults]
    public let recommended: String?
    public let totalReports: Int
    
    public struct GraphicsResults: Codable, Sendable, Equatable {
        public let perfect: Int
        public let issues: Int
        public let broken: Int
        
        public var total: Int { perfect + issues + broken }
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

public struct GameSession: Sendable {
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
