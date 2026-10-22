import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Stops Wine/Steam processes that belong to Vermut-managed prefixes only.
/// Escalation: snapshot PIDs → bounded `wineserver -k` → SIGTERM → SIGKILL.
/// Never targets native macOS apps or non-Vermut Wine installs.
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

    /// One `ps` row: pid, ppid, pgid, command (+ env when listed with `ps -E`).
    public struct ProcessRow: Equatable, Sendable {
        public var pid: pid_t
        public var ppid: pid_t
        public var pgid: pid_t
        public var command: String

        public init(pid: pid_t, ppid: pid_t, pgid: pid_t = 0, command: String) {
            self.pid = pid
            self.ppid = ppid
            self.pgid = pgid
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

    /// `ps -axEww -o pid=,ppid=,pgid=,command=` so WINEPREFIX and groups are visible.
    public static func pidPpidCommandLines() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        #if os(macOS)
        process.arguments = ["-axEww", "-o", "pid=,ppid=,pgid=,command="]
        #else
        process.arguments = ["axeww", "-o", "pid=,ppid=,pgid=,args="]
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
        // pid ppid pgid command…  (pgid optional for legacy 3-field test lines)
        guard parts.count >= 3, let pid = pid_t(parts[0]), let ppid = pid_t(parts[1]) else {
            return nil
        }
        let pgid: pid_t
        let command: String
        if parts.count >= 4, let parsedPgid = pid_t(parts[2]), parts[2].allSatisfy(\.isNumber) {
            pgid = parsedPgid
            // Rejoin command after the three leading integers.
            var rest = trimmed[...]
            for _ in 0..<3 {
                if let space = rest.firstIndex(of: " ") {
                    rest = rest[rest.index(after: space)...].drop(while: { $0.isWhitespace })
                }
            }
            command = String(rest)
        } else {
            pgid = 0
            guard let firstSpace = trimmed.firstIndex(of: " ") else { return nil }
            let afterPid = trimmed[trimmed.index(after: firstSpace)...]
                .drop(while: { $0.isWhitespace })
            guard let secondSpace = afterPid.firstIndex(of: " ") else { return nil }
            command = String(
                afterPid[afterPid.index(after: secondSpace)...]
                    .drop(while: { $0.isWhitespace })
            )
        }
        guard !command.isEmpty else { return nil }
        return ProcessRow(pid: pid, ppid: ppid, pgid: pgid, command: command)
    }

    /// Absolute path of the process executable (`proc_pidpath` on macOS).
    public static func executablePath(for pid: pid_t) -> String? {
        #if os(macOS)
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
        #else
        return nil
        #endif
    }

    /// Open / mapped file paths for a PID (`lsof`). Used when argv has no WINEPREFIX
    /// and `proc_pidpath` is a `$TMPDIR/winetemp-*` Wine loader copy.
    public static func openFilePaths(for pid: pid_t) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // txt = executable, mem = mapped libraries, cwd = working dir.
        process.arguments = ["-a", "-p", "\(pid)", "-d", "txt,mem,cwd", "-Fn"]
        process.standardError = FileHandle.nullDevice
        guard let data = try? ProcessPipe.runReadingStdout(process),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                guard line.hasPrefix("n"), line.count > 1 else { return nil }
                return String(line.dropFirst())
            }
    }

    /// True when `path` is a Vermut-shipped Wine/wineserver/wine-preloader binary.
    public static func isVermutWineExecutable(
        _ path: String,
        enginesRoot: String = PathManager.shared.enginesURL.path
    ) -> Bool {
        let root = normalizedDirectoryPrefix(enginesRoot)
        guard path.hasPrefix(root) || path == enginesRoot else { return false }
        let lower = path.lowercased()
        return lower.contains("/wine") || lower.contains("wineserver") || lower.contains("preloader")
    }

    /// Wine copies its loader into `$TMPDIR/winetemp-<id>-…/` (often named `Steam`).
    public static func isWinetempExecutable(
        _ path: String,
        temporaryDirectory: String = NSTemporaryDirectory()
    ) -> Bool {
        let lower = path.lowercased()
        if lower.contains("/winetemp-") || lower.contains("/winetemp/") { return true }
        let tmp = normalizedDirectoryPrefix(temporaryDirectory)
        return path.hasPrefix(tmp) && lower.contains("winetemp")
    }

    /// Whether open/mapped paths tie the process to Vermut engines or target prefixes.
    /// - Note: `allowEngineOnlyMatch` also allows any path under `bottlesRoot` (full quit).
    ///   When false, only the listed `prefixes` count — shared engines alone are not enough.
    public static func pathsIndicateVermutOwnership(
        _ paths: [String],
        enginesRoot: String,
        bottlesRoot: String,
        prefixes: [String],
        allowEngineOnlyMatch: Bool
    ) -> Bool {
        let enginePrefix = normalizedDirectoryPrefix(enginesRoot)
        let bottlesPrefix = normalizedDirectoryPrefix(bottlesRoot)
        for path in paths {
            if prefixes.contains(where: {
                path.hasPrefix($0) || path.hasPrefix(normalizedDirectoryPrefix($0))
            }) {
                return true
            }
            if allowEngineOnlyMatch {
                if path.hasPrefix(bottlesPrefix) { return true }
                if path.hasPrefix(enginePrefix) { return true }
            }
        }
        return false
    }

    public static func normalizedDirectoryPrefix(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    /// Snapshot every PID that belongs to the given prefixes
    /// (command/env, tree, pgid, Vermut wine path, winetemp + mapped engines files).
    public static func snapshotPrefixPIDs(
        owningPrefixes prefixes: [String],
        rows: [ProcessRow],
        enginesRoot: String = PathManager.shared.enginesURL.path,
        bottlesRoot: String = PathManager.shared.bottlesURL.path,
        executablePathProvider: (pid_t) -> String? = { executablePath(for: $0) },
        openPathsProvider: (pid_t) -> [String] = { openFilePaths(for: $0) },
        currentPID: pid_t = getpid()
    ) -> Set<pid_t> {
        guard !prefixes.isEmpty else { return [] }
        let steamPrefix = PathManager.shared.prefixURL(for: .steam).path
        let includesSteam = prefixes.contains(steamPrefix)
        let allVermut = Set(vermutPrefixPaths())
        let stoppingAll = Set(prefixes).isSuperset(of: allVermut)

        var seeds = Set<pid_t>()
        for row in rows {
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

        // Vermut Wine binary whose argv still names our prefix / bottles path.
        for row in rows {
            guard row.pid > 1, row.pid != currentPID else { continue }
            if isNativeMacApp(row.command) { continue }
            guard let exe = executablePathProvider(row.pid),
                  isVermutWineExecutable(exe, enginesRoot: enginesRoot) else { continue }
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

        let byParent = Dictionary(grouping: rows, by: \.ppid)
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

        // Process-group members of known seeds (when they still share a pgid).
        var seedPgids = Set<pid_t>()
        for row in rows where all.contains(row.pid) {
            if row.pgid > 1 { seedPgids.insert(row.pgid) }
        }
        if !seedPgids.isEmpty {
            for row in rows {
                guard row.pid > 1, row.pid != currentPID, row.pgid > 1 else { continue }
                guard seedPgids.contains(row.pgid) else { continue }
                if isNativeMacApp(row.command) { continue }
                let exe = executablePathProvider(row.pid)
                let vermutWine = exe.map { isVermutWineExecutable($0, enginesRoot: enginesRoot) } ?? false
                if vermutWine || looksLikeWineWindowsProcess(row.command) {
                    all.insert(row.pid)
                }
            }
        }

        // Session-leader orphans (own pgid, ppid 1): bare C:\winedevice.exe.
        // Prefer proc_pidpath under Vermut/engines; else winetemp loader path
        // cross-checked with open/mapped files under engines or target prefixes.
        for row in rows {
            guard row.pid > 1, row.pid != currentPID else { continue }
            if all.contains(row.pid) { continue }
            if isNativeMacApp(row.command) { continue }
            let exe = executablePathProvider(row.pid)
            let winetemp = exe.map { isWinetempExecutable($0) } ?? false
            let vermutExe = exe.map { isVermutWineExecutable($0, enginesRoot: enginesRoot) } ?? false
            let wineLike = looksLikeWineWindowsProcess(row.command)
            let wineserverCmd = row.command.lowercased().contains("wineserver")
            // Full quit: Vermut engine binary + Windows helper argv is enough
            // (covers orphans even when lsof is unavailable).
            if stoppingAll, vermutExe, wineLike || wineserverCmd {
                all.insert(row.pid)
                continue
            }
            guard winetemp || vermutExe || wineLike else { continue }
            let mapped = openPathsProvider(row.pid)
            // winetemp loaders are Vermut Wine copies — engines mapping is enough.
            // Otherwise only claim engine/bottles broadly when stopping every prefix.
            let allowEngines = stoppingAll || winetemp
            if pathsIndicateVermutOwnership(
                mapped,
                enginesRoot: enginesRoot,
                bottlesRoot: bottlesRoot,
                prefixes: prefixes,
                allowEngineOnlyMatch: allowEngines
            ) {
                all.insert(row.pid)
            }
        }

        return all
    }

    /// PIDs that belong to the given Vermut prefixes.
    public static func pids(
        owningPrefixes prefixes: [String],
        processLines: [String]? = nil,
        rows: [ProcessRow]? = nil,
        enginesRoot: String = PathManager.shared.enginesURL.path,
        bottlesRoot: String = PathManager.shared.bottlesURL.path,
        executablePathProvider: (pid_t) -> String? = { executablePath(for: $0) },
        openPathsProvider: (pid_t) -> [String] = { openFilePaths(for: $0) },
        currentPID: pid_t = getpid()
    ) -> [pid_t] {
        guard !prefixes.isEmpty else { return [] }
        let resolvedRows: [ProcessRow]
        if let rows {
            resolvedRows = rows
        } else if let processLines {
            resolvedRows = processLines.compactMap { line -> ProcessRow? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let space = trimmed.firstIndex(of: " "),
                      let pid = pid_t(trimmed[..<space]) else { return nil }
                let cmd = String(trimmed[space...]).trimmingCharacters(in: .whitespaces)
                return ProcessRow(pid: pid, ppid: 0, pgid: 0, command: cmd)
            }
        } else {
            resolvedRows = processRows()
        }
        return snapshotPrefixPIDs(
            owningPrefixes: prefixes,
            rows: resolvedRows,
            enginesRoot: enginesRoot,
            bottlesRoot: bottlesRoot,
            executablePathProvider: executablePathProvider,
            openPathsProvider: openPathsProvider,
            currentPID: currentPID
        ).sorted()
    }

    public static func looksLikeWineWindowsProcess(_ command: String) -> Bool {
        let lower = command.lowercased()
        if isNativeMacApp(command) { return false }
        let markers = [
            #"c:\windows\"#, "c:/windows/", "\\\\windows\\\\",
            "winedevice", "services.exe", "explorer.exe", "plugplay",
            "rpcss", "svchost", "wine-preloader", "wine64", "/wine "
        ]
        return markers.contains(where: { lower.contains($0) })
            || (lower.contains("c:\\") && lower.contains(".exe"))
            || (lower.contains("c:/") && lower.contains(".exe"))
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
        let lower = command.lowercased()
        if command.contains(enginesRoot), prefixes.contains(where: { command.contains($0) }) {
            return true
        }
        if includesSteamBottle {
            if SteamSetupEvaluator.isBottleSteamCommand(command)
                || SteamSetupEvaluator.isBottleWebhelper(command)
                || lower.contains("\\steam\\")
                || lower.contains("/steam/") {
                return true
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

    /// Snapshot PIDs, bounded `wineserver -k`, second discovery sweep, then SIGTERM / SIGKILL.
    @discardableResult
    public static func stopAllVermutPrefixes(
        prefixes: [String]? = nil,
        engineForPrefix: (String) -> WineEngine? = { _ in WineEngine.defaultEngine },
        options: Options = .default,
        sleeper: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        signalSender: (pid_t, Int32) -> Int32 = { kill($0, $1) },
        processLinesProvider: () -> [String] = { PrefixRuntime.processPIDLines() },
        processRowsProvider: (() -> [ProcessRow])? = nil,
        executablePathProvider: @escaping (pid_t) -> String? = { executablePath(for: $0) },
        openPathsProvider: @escaping (pid_t) -> [String] = { openFilePaths(for: $0) },
        wineserverRunner: (URL, String, TimeInterval) -> Void = { wineserver, prefix, timeout in
            runWineserverKill(wineserver: wineserver, prefix: prefix, timeout: timeout)
        }
    ) -> [pid_t] {
        let targets = prefixes ?? vermutPrefixPaths()
        let rowsProvider = processRowsProvider ?? { processRows() }
        let enginesRoot = PathManager.shared.enginesURL.path
        let bottlesRoot = PathManager.shared.bottlesURL.path

        func discover() -> Set<pid_t> {
            let rows = rowsProvider()
            if !rows.isEmpty {
                return snapshotPrefixPIDs(
                    owningPrefixes: targets,
                    rows: rows,
                    enginesRoot: enginesRoot,
                    bottlesRoot: bottlesRoot,
                    executablePathProvider: executablePathProvider,
                    openPathsProvider: openPathsProvider
                )
            }
            return Set(
                pids(
                    owningPrefixes: targets,
                    processLines: processLinesProvider(),
                    enginesRoot: enginesRoot,
                    bottlesRoot: bottlesRoot,
                    executablePathProvider: executablePathProvider,
                    openPathsProvider: openPathsProvider
                )
            )
        }

        // Critical: capture tree/pgid/Vermut-wine PIDs *before* wineserver -k.
        // After -k, helpers reparent to launchd with bare C:\ argv and no WINEPREFIX.
        var recorded = discover()

        for prefix in targets {
            let engine = engineForPrefix(prefix) ?? .defaultEngine
            if let wineserver = PathManager.shared.wineserverExecutable(engine: engine) {
                wineserverRunner(wineserver, prefix, options.wineserverKillTimeout)
            }
        }
        // Bounded pause, then a second sweep for session-leader orphans that the
        // pre-kill tree/pgid snapshot missed (winetemp + mapped engines).
        sleeper(options.afterWineserverSeconds)
        recorded.formUnion(discover())

        for pid in recorded.sorted() {
            _ = signalSender(pid, SIGTERM)
        }
        sleeper(options.termGraceSeconds)

        recorded.formUnion(discover())
        for pid in recorded.sorted() {
            _ = signalSender(pid, SIGKILL)
        }
        sleeper(options.killGraceSeconds)
        return discover().sorted()
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
