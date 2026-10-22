import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Stops Wine/Steam processes that belong to Vermut-managed prefixes only.
/// Escalation: bounded `wineserver -k` → SIGTERM → SIGKILL. Never targets native macOS apps.
public enum PrefixProcessTerminator {
    public struct Options: Sendable {
        public var termGraceSeconds: TimeInterval
        public var killGraceSeconds: TimeInterval
        /// Max time to wait on each `wineserver -k` before abandoning it.
        public var wineserverKillTimeout: TimeInterval
        public var afterWineserverSeconds: TimeInterval

        public init(
            termGraceSeconds: TimeInterval = 1.5,
            killGraceSeconds: TimeInterval = 0.75,
            wineserverKillTimeout: TimeInterval = 2.0,
            afterWineserverSeconds: TimeInterval = 0.25
        ) {
            self.termGraceSeconds = termGraceSeconds
            self.killGraceSeconds = killGraceSeconds
            self.wineserverKillTimeout = wineserverKillTimeout
            self.afterWineserverSeconds = afterWineserverSeconds
        }

        public static let `default` = Options()
    }

    /// One `ps` row: pid, ppid, command (+ env when listed with `ps -E`).
    public struct ProcessRow: Equatable, Sendable {
        public var pid: pid_t
        public var ppid: pid_t
        public var command: String

        public init(pid: pid_t, ppid: pid_t, command: String) {
            self.pid = pid
            self.ppid = ppid
            self.command = command
        }
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
                let prefix = url.appendingPathComponent("prefix")
                if fileManager.fileExists(atPath: prefix.path) {
                    paths.append(prefix.path)
                }
            }
        }
        return paths
    }

    public static func processRows(
        listing: () -> [String] = { Self.pidPpidCommandLines() }
    ) -> [ProcessRow] {
        listing().compactMap(parseProcessLine)
    }

    /// `ps -axEww -o pid=,ppid=,command=` so WINEPREFIX is visible when present.
    public static func pidPpidCommandLines() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        #if os(macOS)
        process.arguments = ["-axEww", "-o", "pid=,ppid=,command="]
        #else
        process.arguments = ["axeww", "-o", "pid=,ppid=,args="]
        #endif
        process.standardError = FileHandle.nullDevice
        guard let data = try? ProcessPipe.runReadingStdout(process) else { return [] }
        return String(data: data, encoding: .utf8)?
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty } ?? []
    }

    public static func parseProcessLine(_ line: String) -> ProcessRow? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard parts.count >= 3,
              let pid = pid_t(parts[0]),
              let ppid = pid_t(parts[1]) else { return nil }
        // Rejoin command from the original line after the two leading integers.
        guard let firstSpace = trimmed.firstIndex(of: " ") else { return nil }
        let afterPid = trimmed[trimmed.index(after: firstSpace)...]
            .drop(while: { $0.isWhitespace })
        guard let secondSpace = afterPid.firstIndex(of: " ") else { return nil }
        let command = afterPid[afterPid.index(after: secondSpace)...]
            .drop(while: { $0.isWhitespace })
        return ProcessRow(pid: pid, ppid: ppid, command: String(command))
    }

    /// PIDs that belong to the given Vermut prefixes (path/env, bottle Steam,
    /// Vermut wine binaries, and their descendant processes).
    public static func pids(
        owningPrefixes prefixes: [String],
        processLines: [String]? = nil,
        rows: [ProcessRow]? = nil,
        enginesRoot: String = PathManager.shared.enginesURL.path,
        bottlesRoot: String = PathManager.shared.bottlesURL.path,
        currentPID: pid_t = getpid()
    ) -> [pid_t] {
        guard !prefixes.isEmpty else { return [] }
        let resolvedRows: [ProcessRow]
        if let rows {
            resolvedRows = rows
        } else if let processLines {
            // Legacy flat "pid command" lines (no ppid) — still match by command.
            resolvedRows = processLines.compactMap { line -> ProcessRow? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let space = trimmed.firstIndex(of: " "),
                      let pid = pid_t(trimmed[..<space]) else { return nil }
                let cmd = String(trimmed[space...]).trimmingCharacters(in: .whitespaces)
                return ProcessRow(pid: pid, ppid: 0, command: cmd)
            }
        } else {
            resolvedRows = processRows()
        }

        let steamPrefix = PathManager.shared.prefixURL(for: .steam).path
        let includesSteam = prefixes.contains(steamPrefix)

        var seeds = Set<pid_t>()
        for row in resolvedRows {
            guard row.pid > 1, row.pid != currentPID else { continue }
            if isNativeMacApp(row.command) { continue }
            if commandBelongsToPrefixes(
                row.command,
                prefixes: prefixes,
                includesSteamBottle: includesSteam,
                enginesRoot: enginesRoot,
                bottlesRoot: bottlesRoot
            ) {
                seeds.insert(row.pid)
            }
        }

        // Expand to descendants so Windows steam.exe / winedevice children are included
        // even when Wine hides WINEPREFIX from their ps lines.
        let byParent = Dictionary(grouping: resolvedRows, by: \.ppid)
        var all = seeds
        var queue = Array(seeds)
        while let pid = queue.popLast() {
            for child in byParent[pid] ?? [] {
                guard child.pid > 1, child.pid != currentPID else { continue }
                if isNativeMacApp(child.command) { continue }
                if all.insert(child.pid).inserted {
                    queue.append(child.pid)
                }
            }
        }
        return all.sorted()
    }

    /// Whether a process command/env line is owned by one of the Vermut prefixes.
    public static func commandBelongsToPrefixes(
        _ command: String,
        prefixes: [String],
        includesSteamBottle: Bool,
        enginesRoot: String = PathManager.shared.enginesURL.path,
        bottlesRoot: String = PathManager.shared.bottlesURL.path
    ) -> Bool {
        if isNativeMacApp(command) { return false }
        if prefixes.contains(where: { command.contains($0) }) { return true }
        if command.contains(bottlesRoot) { return true }
        if includesSteamBottle, SteamSetupEvaluator.isBottleSteamCommand(command) {
            return true
        }
        if includesSteamBottle, SteamSetupEvaluator.isBottleWebhelper(command) {
            return true
        }
        // Wine helpers that only show Windows paths still belong to our bottle when
        // the Unix wine binary is Vermut's and a target prefix is the steam one, or
        // when WINEPREFIX= was already matched above.
        let lower = command.lowercased()
        if command.contains(enginesRoot) {
            // Vermut-shipped wine/wineserver — only claim if a prefix is also named,
            // or the line has WINEPREFIX= for one of our prefixes (handled above),
            // or it's clearly bottle Steam.
            if prefixes.contains(where: { command.contains($0) }) { return true }
            if includesSteamBottle,
               lower.contains("steam") || lower.contains("wineserver") {
                return prefixes.contains(where: { command.contains($0) })
                    || SteamSetupEvaluator.isBottleSteamCommand(command)
            }
        }
        // Common Wine service processes with Windows paths, only with bottle Steam cues
        // or an explicit Vermut bottles / prefix path (already handled).
        if includesSteamBottle {
            let wineServices = [
                "winedevice", "services.exe", "explorer.exe", "plugplay",
                "rpcss", "svchost", "steamservice", "steamwebhelper", "steam.exe"
            ]
            if wineServices.contains(where: { lower.contains($0) }),
               (lower.contains("c:\\") || lower.contains("c:/") || lower.contains(".exe")) {
                // Without a prefix path these are ambiguous unless they're Steam bottle cmds.
                if SteamSetupEvaluator.isBottleSteamCommand(command)
                    || SteamSetupEvaluator.isBottleWebhelper(command)
                    || lower.contains("\\steam\\")
                    || lower.contains("/steam/") {
                    return true
                }
            }
        }
        return false
    }

    /// Heuristic: native Steam/GOG/Epic live under `/Applications` without a Vermut bottle path.
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
        if lower.contains("/application support/vermut/bottles/")
            || lower.contains("/application support/casklauncher/bottles/") {
            return false
        }
        return true
    }

    /// Runs a bounded `wineserver -k`, then SIGTERM / SIGKILL on leftover PIDs.
    @discardableResult
    public static func stopAllVermutPrefixes(
        prefixes: [String]? = nil,
        engineForPrefix: (String) -> WineEngine? = { _ in WineEngine.defaultEngine },
        options: Options = .default,
        sleeper: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        signalSender: (pid_t, Int32) -> Int32 = { kill($0, $1) },
        processLinesProvider: () -> [String] = { PrefixRuntime.processPIDLines() },
        processRowsProvider: (() -> [ProcessRow])? = nil,
        wineserverRunner: (URL, String, TimeInterval) -> Void = { wineserver, prefix, timeout in
            runWineserverKill(wineserver: wineserver, prefix: prefix, timeout: timeout)
        }
    ) -> [pid_t] {
        let targets = prefixes ?? vermutPrefixPaths()
        for prefix in targets {
            let engine = engineForPrefix(prefix) ?? .defaultEngine
            if let wineserver = PathManager.shared.wineserverExecutable(engine: engine) {
                wineserverRunner(wineserver, prefix, options.wineserverKillTimeout)
            }
        }
        sleeper(options.afterWineserverSeconds)

        let rowsProvider = processRowsProvider ?? { processRows() }
        func currentPIDs() -> [pid_t] {
            // Prefer rich pid/ppid rows; fall back to flat lines for tests that inject them.
            let rows = rowsProvider()
            if !rows.isEmpty {
                return pids(owningPrefixes: targets, rows: rows)
            }
            return pids(owningPrefixes: targets, processLines: processLinesProvider())
        }

        var remaining = currentPIDs()
        for pid in remaining {
            _ = signalSender(pid, SIGTERM)
        }
        sleeper(options.termGraceSeconds)

        remaining = currentPIDs()
        for pid in remaining {
            _ = signalSender(pid, SIGKILL)
        }
        sleeper(options.killGraceSeconds)
        return currentPIDs()
    }

    /// `wineserver -k` with a hard timeout — never block quit for tens of seconds.
    public static func runWineserverKill(
        wineserver: URL,
        prefix: String,
        timeout: TimeInterval
    ) {
        let process = Process()
        process.executableURL = wineserver
        process.arguments = ["-k"]
        process.environment = ["WINEPREFIX": prefix]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        _ = ProcessWait.waitUntilExit(process, timeout: timeout)
    }
}
