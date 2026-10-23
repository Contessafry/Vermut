import Foundation

/// Where an effective setting value came from in the
/// Settings (global) → bottle/store → game chain.
public enum InheritanceSource: String, Sendable, Equatable, CaseIterable {
    case global
    case bottle
    case game

    public var userFacingLabel: String {
        switch self {
        case .global: return "Settings"
        case .bottle: return "bottle"
        case .game: return "game"
        }
    }
}

/// Resolved value plus its source. Used by pickers whose first item is
/// `Automatic (…: X)` showing the effective inherited value.
public struct EffectiveSetting<Value: Equatable & Sendable>: Equatable, Sendable {
    public var value: Value
    public var source: InheritanceSource

    public init(value: Value, source: InheritanceSource) {
        self.value = value
        self.source = source
    }
}

/// Sentinel and resolution helpers for Automatic / explicit overrides.
public enum SettingInheritance {
    /// Stored in bottle / future game JSON when the user picks Automatic.
    public static let automatic = "automatic"

    public static func isAutomatic(_ stored: String?) -> Bool {
        guard let stored else { return true }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == automatic
    }

    /// Picker label: `Automatic (default: Vermut Wine)` / `Automatic (Steam: DXMT)`.
    public static func automaticLabel(scope: String, effectiveDisplay: String) -> String {
        "Automatic (\(scope): \(effectiveDisplay))"
    }

    public static func resolveString(
        game: String? = nil,
        bottle: String?,
        global: String
    ) -> EffectiveSetting<String> {
        if let game, !isAutomatic(game) {
            return EffectiveSetting(value: game, source: .game)
        }
        if let bottle, !isAutomatic(bottle) {
            return EffectiveSetting(value: bottle, source: .bottle)
        }
        return EffectiveSetting(value: global, source: .global)
    }

    public static func resolveEngine(
        game: String? = nil,
        bottle: String?,
        global: String
    ) -> EffectiveSetting<WineEngine> {
        let resolved = resolveString(game: game, bottle: bottle, global: global)
        return EffectiveSetting(
            value: WineEngine.resolved(from: resolved.value),
            source: resolved.source
        )
    }

    public static func resolveGraphics(
        game: String? = nil,
        bottle: String?,
        global: String
    ) -> EffectiveSetting<GraphicsBackend> {
        let resolved = resolveString(game: game, bottle: bottle, global: global)
        let backend = GraphicsBackend(rawValue: resolved.value) ?? .dxmt
        return EffectiveSetting(value: backend, source: resolved.source)
    }

    public static func resolveDXMTVersion(
        game: String? = nil,
        bottle: String?,
        global: String
    ) -> EffectiveSetting<String> {
        let resolved = resolveString(game: game, bottle: bottle, global: global)
        return EffectiveSetting(
            value: ComponentVersion.canonicalTag(resolved.value),
            source: resolved.source
        )
    }

    /// Log level chain. When every tier is Automatic, `storeDefault` is used
    /// (Epic → Errors, others → Off) and attributed to `.global`.
    public static func resolveLogLevel(
        game: String? = nil,
        bottle: String? = nil,
        global: String,
        storeDefault: WineLogLevel = .off
    ) -> EffectiveSetting<WineLogLevel> {
        if let game, !isAutomatic(game) {
            return EffectiveSetting(value: WineLogLevel.resolved(from: game), source: .game)
        }
        if let bottle, !isAutomatic(bottle) {
            return EffectiveSetting(value: WineLogLevel.resolved(from: bottle), source: .bottle)
        }
        if !isAutomatic(global) {
            return EffectiveSetting(value: WineLogLevel.resolved(from: global), source: .global)
        }
        return EffectiveSetting(value: storeDefault, source: .global)
    }
}
