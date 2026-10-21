import Foundation

/// Single source of truth for graphics ↔ Wine engine constraints.
/// Vermut Wine (grapple-wine) has no Vulkan loader, so DXVK requires Staging.
public enum EngineGraphicsPolicy {
    /// True when this backend cannot run on Vermut Wine.
    public static func requiresStaging(for backend: GraphicsBackend) -> Bool {
        backend == .dxvk
    }

    /// Display name when Staging is forced by DXVK.
    public static let stagingRequiredByDXVKLabel = "\(WineEngine.staging.userFacingName) (required by DXVK)"

    /// Subtitle for the DXVK graphics option.
    public static let dxvkUsesStagingSubtitle = "Uses Wine Staging"

    /// Apply DXVK→Staging when the inherited engine cannot host Vulkan.
    /// - Returns: launch engine (possibly remapped) and whether Staging was forced for DXVK.
    public static func apply(
        inherited: EffectiveSetting<WineEngine>,
        backend: GraphicsBackend
    ) -> (engine: EffectiveSetting<WineEngine>, forcedForDXVK: Bool) {
        guard requiresStaging(for: backend), inherited.value == .grappleWine else {
            return (inherited, false)
        }
        return (
            EffectiveSetting(value: .staging, source: inherited.source),
            true
        )
    }

    /// Convenience for call sites that only have raw engine + backend.
    public static func launchEngine(
        _ engine: WineEngine,
        backend: GraphicsBackend
    ) -> WineEngine {
        apply(
            inherited: EffectiveSetting(value: engine, source: .global),
            backend: backend
        ).engine.value
    }

    /// Picker / help label for an engine given the effective graphics backend.
    public static func enginePickerLabel(
        for engine: WineEngine,
        effectiveBackend: GraphicsBackend,
        statusSuffix: String
    ) -> String {
        if requiresStaging(for: effectiveBackend), engine == .staging {
            return "\(stagingRequiredByDXVKLabel) · \(statusSuffix)"
        }
        if requiresStaging(for: effectiveBackend), engine == .grappleWine {
            // Vermut Wine cannot satisfy DXVK — still listed but marked.
            return "\(engine.userFacingName) · unavailable with DXVK"
        }
        return "\(engine.userFacingName) · \(statusSuffix)"
    }

    public static func graphicsPickerLabel(for backend: GraphicsBackend) -> String {
        if backend == .dxvk {
            return "\(backend.shortLabel) · \(dxvkUsesStagingSubtitle)"
        }
        return backend.shortLabel
    }
}
