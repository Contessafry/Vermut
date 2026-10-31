import Foundation

/// Engine + graphics last applied to the Steam bottle session.
public struct BottleRuntimeProfile: Equatable, Sendable {
    public var engine: WineEngine
    public var graphics: GraphicsBackend
    public var steamOverlayEnabled: Bool

    public init(engine: WineEngine, graphics: GraphicsBackend, steamOverlayEnabled: Bool = false) {
        self.engine = engine
        self.graphics = graphics
        self.steamOverlayEnabled = steamOverlayEnabled
    }

    public init(resolved: ResolvedLaunchSettings) {
        self.engine = resolved.engine.value
        self.graphics = resolved.graphics.value
        self.steamOverlayEnabled = resolved.steamOverlayEnabled
    }
}

/// Pure helpers for launching a Steam title with per-game settings.
public enum SteamGameLaunch {
    /// Steam argv that starts (or forwards to) a specific app.
    public static func applaunchArguments(appId: String, firstRunUpdate: Bool = false) -> [String] {
        if firstRunUpdate {
            return ["steam.exe"]
        }
        return [
            "steam.exe",
            "-no-cef-sandbox",
            "-cef-disable-gpu",
            "-noverifyfiles",
            "-applaunch",
            appId
        ]
    }

    /// `steam://rungameid/<appId>` URI for an already-running client.
    public static func rungameURI(appId: String) -> String {
        "steam://rungameid/\(appId)"
    }

    /// Restart when the running client uses a different engine (or known graphics profile).
    public static func needsClientRestart(
        isRunning: Bool,
        runningProfile: BottleRuntimeProfile?,
        runningEngineFromProcess: WineEngine?,
        needed: BottleRuntimeProfile
    ) -> Bool {
        guard isRunning else { return false }
        if let runningProfile, runningProfile != needed {
            return true
        }
        if let runningEngineFromProcess, runningEngineFromProcess != needed.engine {
            return true
        }
        return false
    }

    public static func restartInfoMessage(neededEngine: WineEngine) -> String {
        "This game needs \(neededEngine.userFacingName). Steam will quit and reopen with that engine."
    }

    /// WINEDEBUG for the Steam client / shared wineserver — never game Verbose.
    public static func clientWineDebug(
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        WineLogLevel.effectiveWineDebug(level: .off, processEnvironment: processEnvironment)
    }

    /// Infer the engine of a live Steam bottle from wine/wineserver paths in `ps` lines.
    public static func detectRunningEngine(
        prefixPath: String,
        processLines: [String],
        engineInstallPaths: [WineEngine: String]
    ) -> WineEngine? {
        let relevant = processLines.filter { line in
            line.contains(prefixPath) || line.lowercased().contains("wineserver")
        }
        for (engine, root) in engineInstallPaths {
            guard !root.isEmpty else { continue }
            if relevant.contains(where: { $0.contains(root) }) {
                return engine
            }
        }
        // Fallback: any process line mentioning an engine install root + steam bottle wineserver.
        for (engine, root) in engineInstallPaths {
            guard !root.isEmpty else { continue }
            let hit = processLines.contains { line in
                line.contains(root)
                    && (line.lowercased().contains("wineserver") || line.lowercased().contains("/wine"))
            }
            if hit {
                // Prefer lines that also mention the prefix when possible.
                let withPrefix = processLines.contains { $0.contains(root) && $0.contains(prefixPath) }
                if withPrefix { return engine }
            }
        }
        for (engine, root) in engineInstallPaths {
            guard !root.isEmpty else { continue }
            if processLines.contains(where: { $0.contains(root) && $0.lowercased().contains("wineserver") }) {
                return engine
            }
        }
        return nil
    }
}
