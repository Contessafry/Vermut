import Foundation

/// A locally created Wine prefix outside Steam / Epic / GOG.
public struct CustomBottle: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var configuration: BottleConfiguration
    public var programs: [BottleProgram]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        configuration: BottleConfiguration = BottleConfiguration(),
        programs: [BottleProgram] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.configuration = configuration
        self.programs = programs
    }
}

public struct BottleProgram: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var displayName: String
    /// Windows-style path, e.g. `C:\Program Files\UDB\Builder.exe`.
    public var windowsPath: String
    public var kind: Kind
    public var lastRunAt: Date?

    public enum Kind: String, Codable, Sendable, Equatable {
        case launched
        case shortcut
        case installer
    }

    public init(
        id: UUID = UUID(),
        displayName: String,
        windowsPath: String,
        kind: Kind,
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.windowsPath = windowsPath
        self.kind = kind
        self.lastRunAt = lastRunAt
    }
}

/// Non-persisted lifecycle for a custom bottle.
public enum BottleRuntimeState: Sendable, Equatable {
    case idle
    case creating(progress: Double)
    case downloading(component: String, progress: Double)
    case running(pids: [Int32])
    case error(message: String)
}

/// Windows version tags accepted by winecfg / the New Bottle sheet.
public enum BottleWindowsVersion: String, CaseIterable, Identifiable, Sendable {
    case win10
    case win81
    case win7

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .win10: return "Windows 10"
        case .win81: return "Windows 8.1"
        case .win7: return "Windows 7"
        }
    }
}

/// Pure name validation for the New Bottle sheet (trim + rules from the beta spec).
public enum BottleNameValidator {
    public static let maxLength = 40

    /// Characters that must not appear in a bottle name.
    public static let forbiddenCharacters = CharacterSet(charactersIn: "/:\\*?\"<>|")
        .union(.controlCharacters)

    public enum Failure: Equatable, Sendable {
        case empty
        case duplicate(existingName: String)
        case invalidCharacters
        case tooLong
    }

    /// Names reserved by store bottles (case-insensitive).
    public static var reservedStoreNames: [String] {
        GameStore.allCases.flatMap { store in
            [store.rawValue, store.identifier]
        } + ["Steam", "Epic Games", "Epic Games Store", "GOG Galaxy", "GOG"]
    }

    public static func validate(
        _ raw: String,
        existingNames: [String],
        excludingID: UUID? = nil
    ) -> Failure? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .empty }
        if name.count > maxLength { return .tooLong }
        if name.unicodeScalars.contains(where: { forbiddenCharacters.contains($0) }) {
            return .invalidCharacters
        }
        let lowered = name.lowercased()
        for reserved in reservedStoreNames {
            if reserved.lowercased() == lowered {
                return .duplicate(existingName: reserved)
            }
        }
        for existing in existingNames {
            if existing.lowercased() == lowered {
                return .duplicate(existingName: existing)
            }
        }
        return nil
    }

    public static func errorMessage(for failure: Failure) -> String {
        switch failure {
        case .empty:
            return "Enter a name."
        case .duplicate(let existingName):
            return "A bottle named “\(existingName)” already exists."
        case .invalidCharacters:
            return "Names can’t contain / : \\ * ? \" < > |."
        case .tooLong:
            return "Use \(maxLength) characters or fewer."
        }
    }

    /// Suggests `New Bottle`, `New Bottle 2`, … avoiding collisions.
    public static func suggestedName(existingNames: [String]) -> String {
        let lowered = Set(existingNames.map { $0.lowercased() } + reservedStoreNames.map { $0.lowercased() })
        let base = "New Bottle"
        if !lowered.contains(base.lowercased()) { return base }
        var index = 2
        while lowered.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }
}
