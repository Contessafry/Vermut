import Foundation

/// Semantic version with optional pre-release identifiers (e.g. `1.2.0-beta.1`).
/// Comparison follows SemVer 2.0: `1.2.0` > `1.2.0-beta.2` > `1.2.0-beta.1`.
public struct SemVer: Equatable, Comparable, Sendable, Hashable {
    public var major: Int
    public var minor: Int
    public var patch: Int
    /// Dot-separated pre-release identifiers after `-` (empty = stable release).
    public var prereleaseIdentifiers: [String]

    public var isPrerelease: Bool { !prereleaseIdentifiers.isEmpty }

    public init(major: Int, minor: Int, patch: Int, prereleaseIdentifiers: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = prereleaseIdentifiers
    }

    /// Parses tags like `v1.2.0`, `1.2.0-beta.1`, `v1.2.0-rc.2`. Build metadata (`+…`) is ignored.
    public static func parse(_ raw: String) -> SemVer? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value = String(value.dropFirst())
        }
        if let plus = value.firstIndex(of: "+") {
            value = String(value[..<plus])
        }
        guard !value.isEmpty else { return nil }

        let coreAndPre = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = String(coreAndPre[0])
        let prerelease: [String]
        if coreAndPre.count > 1 {
            prerelease = String(coreAndPre[1])
                .split(separator: ".")
                .map(String.init)
                .filter { !$0.isEmpty }
        } else {
            prerelease = []
        }

        let parts = core.split(separator: ".").map(String.init)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        guard let major = Int(parts[0]) else { return nil }
        let minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
        // Reject non-numeric core segments (except we already parsed Int).
        if parts.count > 1, Int(parts[1]) == nil { return nil }
        if parts.count > 2, Int(parts[2]) == nil { return nil }

        return SemVer(major: major, minor: minor, patch: patch, prereleaseIdentifiers: prerelease)
    }

    /// True when the tag string denotes a pre-release (parsed or heuristic).
    public static func tagIsPrerelease(_ tag: String) -> Bool {
        if let parsed = parse(tag) { return parsed.isPrerelease }
        let lower = tag.lowercased()
        return lower.contains("-beta") || lower.contains("-rc") || lower.contains("-alpha")
            || lower.contains("-pre")
    }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // Same core version: stable (no prerelease) > any prerelease.
        switch (lhs.isPrerelease, rhs.isPrerelease) {
        case (false, true): return false
        case (true, false): return true
        case (false, false): return false
        case (true, true):
            return comparePrerelease(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) == .orderedAscending
        }
    }

    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        guard let left = parse(lhs), let right = parse(rhs) else {
            let a = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            let b = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
            return a.localizedStandardCompare(b)
        }
        if left < right { return .orderedAscending }
        if right < left { return .orderedDescending }
        return .orderedSame
    }

    private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            if index >= lhs.count { return .orderedAscending } // fewer identifiers → lower
            if index >= rhs.count { return .orderedDescending }
            let result = compareIdentifier(lhs[index], rhs[index])
            if result != .orderedSame { return result }
        }
        return .orderedSame
    }

    private static func compareIdentifier(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftNum = Int(lhs)
        let rightNum = Int(rhs)
        switch (leftNum, rightNum) {
        case let (l?, r?):
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
            return .orderedSame
        case (_?, nil):
            return .orderedAscending // numeric < alphanumeric
        case (nil, _?):
            return .orderedDescending
        default:
            return lhs.localizedStandardCompare(rhs)
        }
    }
}

/// In-app update feed: Stable (default) or Beta (includes GitHub pre-releases).
public enum UpdateChannel: String, CaseIterable, Identifiable, Codable, Sendable {
    case stable
    case beta

    public var id: String { rawValue }

    public var userFacingName: String {
        switch self {
        case .stable: return "Stable"
        case .beta: return "Beta"
        }
    }

    public static func resolved(from stored: String?) -> UpdateChannel {
        guard let stored, let channel = UpdateChannel(rawValue: stored) else { return .stable }
        return channel
    }
}
