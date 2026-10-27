import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Identifies the game's Wine processes so we can stop a probe without tearing down Steam.
public enum FindGameProcess {
    public struct Snapshot: Sendable, Equatable {
        public var gamePIDs: [pid_t]
        public var steamClientPIDs: [pid_t]
        public var wineserverPIDs: [pid_t]

        public init(gamePIDs: [pid_t] = [], steamClientPIDs: [pid_t] = [], wineserverPIDs: [pid_t] = []) {
            self.gamePIDs = gamePIDs
            self.steamClientPIDs = steamClientPIDs
            self.wineserverPIDs = wineserverPIDs
        }

        public var isGameAlive: Bool { !gamePIDs.isEmpty }
    }

    /// Steam / CEF / overlay helpers — never treated as the game.
    public static let steamClientTokens: [String] = [
        "steam.exe",
        "steamwebhelper",
        "gameoverlayui",
        "steamerrorreporter",
        "crashhandler",
        "steamservice.exe"
    ]

    /// Host Wine pieces that must stay up when we only want the title gone.
    public static let hostKeepTokens: [String] = [
        "wineserver",
        "wineboot",
        "winedevice",
        "plugplay.exe",
        "services.exe",
        "rpcss.exe",
        "explorer.exe"
    ]

    public static func classify(
        processLines: [String],
        prefixPath: String,
        installDir: String?,
        appId: String
    ) -> Snapshot {
        var game: [pid_t] = []
        var steam: [pid_t] = []
        var servers: [pid_t] = []

        for line in processLines {
            guard let pid = pid(from: line) else { continue }
            let command = commandPortion(of: line)
            if isWineserver(command) {
                if belongsToPrefix(command, prefixPath: prefixPath) {
                    servers.append(pid)
                }
                continue
            }
            if isSteamClient(command) {
                steam.append(pid)
                continue
            }
            if isHostKeep(command) {
                continue
            }
            if isGameCommand(command, installDir: installDir, appId: appId, prefixPath: prefixPath) {
                game.append(pid)
            }
        }

        return Snapshot(
            gamePIDs: Array(Set(game)).sorted(),
            steamClientPIDs: Array(Set(steam)).sorted(),
            wineserverPIDs: Array(Set(servers)).sorted()
        )
    }

    public static func isSteamClient(_ command: String) -> Bool {
        let lower = command.lowercased()
        return steamClientTokens.contains { lower.contains($0) }
    }

    public static func isWineserver(_ command: String) -> Bool {
        command.lowercased().contains("wineserver")
    }

    public static func isHostKeep(_ command: String) -> Bool {
        let lower = command.lowercased()
        return hostKeepTokens.contains { lower.contains($0) }
    }

    public static func isGameCommand(
        _ command: String,
        installDir: String?,
        appId: String,
        prefixPath: String
    ) -> Bool {
        if isSteamClient(command) || isWineserver(command) || isHostKeep(command) {
            return false
        }
        if PrefixProcessTerminator.isDeniedForeignPath(command) {
            return false
        }
        let lower = command.lowercased()
        let looksWindowsExe = lower.contains(".exe") || lower.contains("c:\\") || lower.contains("c:/")
        if let installDir, !installDir.isEmpty {
            let needle = installDir.lowercased()
            if lower.contains(needle), looksWindowsExe || lower.contains("steamapps") {
                return true
            }
        }
        if !appId.isEmpty, appId.allSatisfy(\.isNumber) {
            if lower.contains("steamapps") && lower.contains(appId) && looksWindowsExe {
                return true
            }
        }
        // Last resort: a Windows exe in this prefix that is not Steam itself.
        if !prefixPath.isEmpty, command.contains(prefixPath), looksWindowsExe, !isSteamClient(command) {
            return true
        }
        return false
    }

    public static func belongsToPrefix(_ command: String, prefixPath: String) -> Bool {
        if prefixPath.isEmpty { return true }
        return command.contains(prefixPath)
    }

    public static func pid(from line: String) -> pid_t? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(of: " ") else { return pid_t(trimmed) }
        return pid_t(trimmed[..<space])
    }

    public static func commandPortion(of line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(of: " ") else { return trimmed }
        return String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
    }

    /// SIGTERM then SIGKILL only the given PIDs. Never touches wineserver / Steam unless they are in `pids`.
    @discardableResult
    public static func stop(
        pids: [pid_t],
        termGraceSeconds: TimeInterval = 0.6,
        killGraceSeconds: TimeInterval = 0.25,
        sleeper: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        signalSender: (pid_t, Int32) -> Int32 = { kill($0, $1) }
    ) -> [pid_t] {
        let unique = Array(Set(pids.filter { $0 > 1 })).sorted()
        for pid in unique {
            _ = signalSender(pid, SIGTERM)
        }
        if termGraceSeconds > 0 {
            sleeper(termGraceSeconds)
        }
        for pid in unique {
            _ = signalSender(pid, SIGKILL)
        }
        if killGraceSeconds > 0 {
            sleeper(killGraceSeconds)
        }
        return unique
    }

    /// Whether the next combo needs a Steam/client restart (engine, graphics, or overlay changed).
    public static func needsStoreRestart(
        current: FindConfigurationCombo?,
        next: FindConfigurationCombo
    ) -> Bool {
        guard let current else { return true }
        return current.runtimeProfile != next.runtimeProfile
    }
}
