import Foundation

/// Per-game / bottle / Settings log verbosity mapped to `WINEDEBUG`.
/// Host env `VERMUT_WINEDEBUG` always wins when set.
public enum WineLogLevel: String, CaseIterable, Identifiable, Sendable, Codable {
    case off
    case errors
    case verbose

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .errors: return "Errors"
        case .verbose: return "Verbose"
        }
    }

    /// Value written to `WINEDEBUG` when `VERMUT_WINEDEBUG` is unset.
    public var wineDebug: String {
        switch self {
        case .off: return "-all"
        case .errors: return "err+all,fixme-all"
        case .verbose: return "warn+all,err+all"
        }
    }

    public static func resolved(from stored: String) -> WineLogLevel {
        WineLogLevel(rawValue: stored) ?? .off
    }

    /// Soft default when Settings / bottle leave Automatic (Epic keeps Errors for DXVK faults).
    public static func storeDefault(for store: GameStore) -> WineLogLevel {
        store == .epic ? .errors : .off
    }

    /// Prefer `VERMUT_WINEDEBUG` when set; otherwise the level’s `WINEDEBUG` string.
    public static func effectiveWineDebug(
        level: WineLogLevel,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let override = processEnvironment["VERMUT_WINEDEBUG"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        return level.wineDebug
    }
}
