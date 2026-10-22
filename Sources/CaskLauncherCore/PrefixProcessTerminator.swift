import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Stops Wine/Steam processes that belong to Vermut-managed prefixes only.
/// Escalation: `wineserver -k` → SIGTERM → SIGKILL. Never targets native macOS apps.
public enum PrefixProcessTerminator {
    public struct Options: Sendable {
        public var termGraceSeconds: TimeInterval
        public var killGraceSeconds: TimeInterval
        public var wineserverWaitSeconds: TimeInterval

        public init(
            termGraceSeconds: TimeInterval = 2.0,
            killGraceSeconds: TimeInterval = 1.0,
            wineserverWaitSeconds: TimeInterval = 2.0
        ) {
            self.termGraceSeconds = termGraceSeconds
            self.killGraceSeconds = killGraceSeconds
            self.wineserverWaitSeconds = wineserverWaitSeconds
        }

        public static let `default` = Options()
    }

    /// Collects every Vermut bottle prefix (store + custom).
    public static func vermutPrefixPaths(
        bottlesRoot: URL = PathManager.shared.bottlesURL,
        fileManager: FileManager = .default
    ) -> [String] {
        var paths: [String] = []
        for store in GameStore.allCases {
            paths.append(PathManager.shared.prefixURL(for: store).path)
        }
        if let customIDs = try? fileManager.contentsOfDirectory(
            at: bottlesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let storeIDs = Set(GameStore.allCases.map(\.identifier))
            for url in customIDs {
                let name = url.lastPathComponent
                if storeIDs.contains(name) { continue }
                // UUID folders or legacy `custom`
                let prefix = url.appendingPathComponent("prefix")
                if fileManager.fileExists(atPath: prefix.path) {
                    paths.append(prefix.path)
                }
            }
        }
        return paths
    }

    /// PIDs whose `ps` line references one of the given prefix paths.
    /// Excludes the current process and obvious native Mac app bundles.
    public static func pids(
        owningPrefixes prefixes: [String],
        processLines: [String] = PrefixRuntime.processPIDLines(),
        currentPID: pid_t = getpid()
    ) -> [pid_t] {
        guard !prefixes.isEmpty else { return [] }
        var result: [pid_t] = []
        for line in processLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = pid_t(trimmed[..<space]),
                  pid > 1,
                  pid != currentPID else { continue }
            let cmd = String(trimmed[space...])
            if isNativeMacApp(cmd) { continue }
            if prefixes.contains(where: { cmd.contains($0) }) {
                result.append(pid)
            }
        }
        return Array(Set(result)).sorted()
    }

    /// Heuristic: native Steam/GOG/Epic live under `/Applications` or `~/Applications`
    /// without a Vermut `WINEPREFIX=` / bottles path in the command line.
    public static func isNativeMacApp(_ command: String) -> Bool {
        let lower = command.lowercased()
        let looksNativeBundle =
            lower.contains("/applications/steam.app/")
            || lower.contains("/applications/steam.app ")
            || lower.contains("steam_osx")
            || lower.contains("/applications/epic games launcher.app/")
            || lower.contains("/applications/gog galaxy.app/")
            || lower.contains("/applications/galaxyclient.app/")
        if !looksNativeBundle { return false }
        // If the line also names a Vermut bottle path, it is Wine-hosted — keep it.
        if lower.contains("/application support/vermut/bottles/")
            || lower.contains("/application support/casklauncher/bottles/") {
            return false
        }
        return true
    }

    /// Runs wineserver -k for each prefix that has a known engine binary, then
    /// escalates to SIGTERM / SIGKILL on leftover PIDs for those prefixes only.
    @discardableResult
    public static func stopAllVermutPrefixes(
        prefixes: [String]? = nil,
        engineForPrefix: (String) -> WineEngine? = { _ in WineEngine.defaultEngine },
        options: Options = .default,
        sleeper: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        signalSender: (pid_t, Int32) -> Int32 = { kill($0, $1) },
        processLinesProvider: () -> [String] = { PrefixRuntime.processPIDLines() },
        wineserverRunner: (URL, String) -> Void = { wineserver, prefix in
            let process = Process()
            process.executableURL = wineserver
            process.arguments = ["-k"]
            process.environment = ["WINEPREFIX": prefix]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    ) -> [pid_t] {
        let targets = prefixes ?? vermutPrefixPaths()
        for prefix in targets {
            let engine = engineForPrefix(prefix) ?? .defaultEngine
            if let wineserver = PathManager.shared.wineserverExecutable(engine: engine) {
                wineserverRunner(wineserver, prefix)
            }
        }
        sleeper(options.wineserverWaitSeconds)

        var remaining = pids(owningPrefixes: targets, processLines: processLinesProvider())
        for pid in remaining {
            _ = signalSender(pid, SIGTERM)
        }
        sleeper(options.termGraceSeconds)

        remaining = pids(owningPrefixes: targets, processLines: processLinesProvider())
        for pid in remaining {
            _ = signalSender(pid, SIGKILL)
        }
        sleeper(options.killGraceSeconds)
        return pids(owningPrefixes: targets, processLines: processLinesProvider())
    }
}
