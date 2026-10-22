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
        /// Hard ceiling for the whole quit cleanup (discover + wineserver + signals).
        public var totalBudgetSeconds: TimeInterval

        public init(
            termGraceSeconds: TimeInterval = 0.75,
            killGraceSeconds: TimeInterval = 0.35,
            wineserverKillTimeout: TimeInterval = 1.5,
            afterWineserverSeconds: TimeInterval = 0.15,
            totalBudgetSeconds: TimeInterval = 10
        ) {
            self.termGraceSeconds = termGraceSeconds
            self.killGraceSeconds = killGraceSeconds
            self.wineserverKillTimeout = wineserverKillTimeout
            self.afterWineserverSeconds = afterWineserverSeconds
            self.totalBudgetSeconds = totalBudgetSeconds
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
    /// Bounded so a stuck `lsof` cannot stall quit.
    public static func openFilePaths(for pid: pid_t, timeout: TimeInterval = 0.4) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // txt = executable, mem = mapped libraries, cwd = working dir.
        process.arguments = ["-a", "-p", "\(pid)", "-d", "txt,mem,cwd", "-Fn"]
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return [] }
        let waitResult = ProcessWait.waitUntilExit(
            process,
            timeout: timeout,
            escalateGrace: 0.15
        )
        let data: Data
        switch waitResult {
        case .exited:
            data = pipe.fileHandleForReading.readDataToEndOfFile()
        case .timedOut:
            // Best-effort drain; process was killed by waitUntilExit.
            data = pipe.fileHandleForReading.readDataToEndOfFile()
        }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
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
        if isDeniedForeignPath(path) { return false }
        let root = normalizedDirectoryPrefix(enginesRoot)
        guard path.hasPrefix(root) || path == enginesRoot else { return false }
        let lower = path.lowercased()
        return lower.contains("/wine") || lower.contains("wineserver") || lower.contains("preloader")
    }

    /// Wine copies its loader into `$TMPDIR/winetemp-<id>-…/` (often named `Steam`).
    /// Name alone is never ownership — must be cross-checked with mapped Vermut files.
    public static func isWinetempExecutable(
        _ path: String,
        temporaryDirectory: String = NSTemporaryDirectory()
    ) -> Bool {
        if isDeniedForeignPath(path) { return false }
        let lower = path.lowercased()
        if lower.contains("/winetemp-") || lower.contains("/winetemp/") { return true }
        let tmp = normalizedDirectoryPrefix(temporaryDirectory)
        return path.hasPrefix(tmp) && lower.contains("winetemp")
    }

    /// Loader we may treat as a Vermut Wine candidate (engines binary or winetemp copy).
    public static func isVermutLoaderExecutable(
        _ path: String,
        enginesRoot: String = PathManager.shared.enginesURL.path,
        temporaryDirectory: String = NSTemporaryDirectory()
    ) -> Bool {
        isVermutWineExecutable(path, enginesRoot: enginesRoot)
            || isWinetempExecutable(path, temporaryDirectory: temporaryDirectory)
    }

    /// Whether open/mapped paths tie the process to Vermut engines or target prefixes.
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
            if isDeniedForeignPath(path) { continue }
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

    /// Strict orphan ownership: Vermut/winetemp loader **and** mapped engines/prefix files.
    public static func processOwnedByVermut(
        executablePath: String?,
        openPaths: [String],
        enginesRoot: String,
        bottlesRoot: String,
        prefixes: [String]
    ) -> Bool {
        guard let exe = executablePath, isVermutLoaderExecutable(exe, enginesRoot: enginesRoot) else {
            return false
        }
        if isDeniedForeignPath(exe) { return false }
        return pathsIndicateVermutOwnership(
            openPaths,
            enginesRoot: enginesRoot,
            bottlesRoot: bottlesRoot,
            prefixes: prefixes,
            allowEngineOnlyMatch: true
        )
    }

    public static func normalizedDirectoryPrefix(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    /// Never signal native Steam/GOG/Epic, Grapple.app, CrossOver, or other .app bundles.
    /// - Important: Does **not** deny `$TMPDIR/winetemp-*/Steam`, Vermut prefixes
    ///   (`…/drive_c/Program Files (x86)/Steam`), or `…/engines/grapple-wine/…`.
    public static func isDeniedForeignPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        // Positive allow: Wine loader temp copies and Vermut-managed trees.
        if lower.contains("/winetemp-") || lower.contains("/winetemp/") { return false }
        if lower.contains("/application support/vermut/")
            || lower.contains("/application support/casklauncher/") {
            return false
        }
        // Native Steam only (App Support bundle / ipcserver / Steam.app) — never
        // bottle paths that merely contain "/Steam" in the name.
        if lower.contains("/library/application support/steam/") { return true }
        if lower.contains("steam.app/") || lower.contains("/steam.app ") { return true }
        if lower.contains("steam_osx") { return true }
        if lower.hasSuffix("/ipcserver"), lower.contains("/application support/steam") {
            return true
        }
        // Foreign launchers — match app bundles / their App Support dirs only.
        // Do NOT match `…/engines/grapple-wine/…` (Vermut engine id).
        if lower.contains("/application support/gog.com") { return true }
        if lower.contains("/application support/grapple/") { return true }
        if lower.contains("/application support/crossover") { return true }
        if lower.contains("/applications/"), lower.contains(".app/") { return true }
        return false
    }

    public static func isDeniedForeignProcess(executablePath: String?, command: String) -> Bool {
        if isDeniedForeignPath(command) { return true }
        if let executablePath, isDeniedForeignPath(executablePath) { return true }
        return false
    }

    /// Snapshot every PID that belongs to the given prefixes
    /// (command/env path match, tree, pgid + Vermut loader, winetemp/engines AND mapped files).
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

        // Cache proc_pidpath / lsof — never lsof the whole process table.
        var exeCache: [pid_t: String?] = [:]
        var openCache: [pid_t: [String]] = [:]
        func exe(for pid: pid_t) -> String? {
            if let cached = exeCache[pid] { return cached }
            let value = executablePathProvider(pid)
            exeCache[pid] = value
            return value
        }
        func openPaths(for pid: pid_t) -> [String] {
            if let cached = openCache[pid] { return cached }
            let value = openPathsProvider(pid)
            openCache[pid] = value
            return value
        }
        func denied(_ row: ProcessRow) -> Bool {
            // Cheap command check first; resolve exe only when needed.
            if isDeniedForeignPath(row.command) { return true }
            if let path = exe(for: row.pid), isDeniedForeignPath(path) { return true }
            return false
        }

        var seeds = Set<pid_t>()
        for row in rows {
            guard row.pid > 1, row.pid != currentPID else { continue }
            if denied(row) { continue }
            // Positive path ownership only (WINEPREFIX / bottles / engines+prefix in argv).
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
            if seeds.contains(row.pid) { continue }
            if denied(row) { continue }
            guard let path = exe(for: row.pid),
                  isVermutWineExecutable(path, enginesRoot: enginesRoot) else { continue }
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
                if denied(child) { continue }
                if all.insert(child.pid).inserted {
                    queue.append(child.pid)
                }
            }
        }

        // Process-group members of known seeds: require Vermut/winetemp loader
        // (never claim by Windows argv or process name alone).
        var seedPgids = Set<pid_t>()
        for row in rows where all.contains(row.pid) {
            if row.pgid > 1 { seedPgids.insert(row.pgid) }
        }
        if !seedPgids.isEmpty {
            for row in rows {
                guard row.pid > 1, row.pid != currentPID, row.pgid > 1 else { continue }
                guard seedPgids.contains(row.pgid) else { continue }
                if all.contains(row.pid) { continue }
                if denied(row) { continue }
                let path = exe(for: row.pid)
                if let path, isVermutWineExecutable(path, enginesRoot: enginesRoot) {
                    all.insert(row.pid)
                    continue
                }
                // Only lsof winetemp / wine-like candidates in the seed pgid.
                let wineLike = looksLikeWineWindowsProcess(row.command)
                let winetemp = path.map { isWinetempExecutable($0) } ?? false
                guard winetemp || wineLike else { continue }
                if processOwnedByVermut(
                    executablePath: path,
                    openPaths: openPaths(for: row.pid),
                    enginesRoot: enginesRoot,
                    bottlesRoot: bottlesRoot,
                    prefixes: prefixes
                ) {
                    all.insert(row.pid)
                }
            }
        }

        // Session-leader orphans: loader under engines or winetemp-* AND mapped
        // files under engines/prefix. Never match by name ("Steam" / "steam").
        // Only run lsof for plausible Vermut Wine candidates.
        for row in rows {
            guard row.pid > 1, row.pid != currentPID else { continue }
            if all.contains(row.pid) { continue }
            if isDeniedForeignPath(row.command) { continue }
            let path = exe(for: row.pid)
            if let path, isDeniedForeignPath(path) { continue }
            let winetemp = path.map { isWinetempExecutable($0) } ?? false
            let vermutExe = path.map { isVermutWineExecutable($0, enginesRoot: enginesRoot) } ?? false
            let wineLike = looksLikeWineWindowsProcess(row.command)
                || SteamSetupEvaluator.isBottleWebhelper(row.command)
                || SteamSetupEvaluator.isBottleSteamCommand(row.command)
            guard winetemp || vermutExe || wineLike else { continue }
            if processOwnedByVermut(
                executablePath: path,
                openPaths: openPaths(for: row.pid),
                enginesRoot: enginesRoot,
                bottlesRoot: bottlesRoot,
                prefixes: prefixes
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
        if isDeniedForeignPath(command) { return false }
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
    /// Positive path matches only — never claim by process name ("Steam" / "/steam/").
    public static func commandBelongsToPrefixes(
        _ command: String,
        prefixes: [String],
        includesSteamBottle: Bool,
        enginesRoot: String = PathManager.shared.enginesURL.path,
        bottlesRoot: String = PathManager.shared.bottlesURL.path
    ) -> Bool {
        if isDeniedForeignPath(command) { return false }
        if prefixes.contains(where: { command.contains($0) }) { return true }
        if command.contains(bottlesRoot) { return true }
        // Windows-in-Wine argv (C:\…\Steam\…) — not native macOS paths.
        if includesSteamBottle, SteamSetupEvaluator.isBottleSteamCommand(command) {
            return true
        }
        if includesSteamBottle, SteamSetupEvaluator.isBottleWebhelper(command) {
            return true
        }
        if command.contains(enginesRoot), prefixes.contains(where: { command.contains($0) }) {
            return true
        }
        return false
    }

    /// Heuristic: native Steam/GOG/Epic / foreign Wine stacks — never signal these.
    public static func isNativeMacApp(_ command: String) -> Bool {
        isDeniedForeignPath(command)
    }

    /// Snapshot PIDs, bounded `wineserver -k`, second discovery sweep, then SIGTERM / SIGKILL.
    /// Honors `options.totalBudgetSeconds` so app quit stays near ~10s.
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
        },
        now: () -> Date = { Date() }
    ) -> [pid_t] {
        let targets = prefixes ?? vermutPrefixPaths()
        let rowsProvider = processRowsProvider ?? { processRows() }
        let enginesRoot = PathManager.shared.enginesURL.path
        let bottlesRoot = PathManager.shared.bottlesURL.path
        let deadline = now().addingTimeInterval(options.totalBudgetSeconds)

        func budgetLeft() -> TimeInterval {
            max(0, deadline.timeIntervalSince(now()))
        }
        func sleepBudget(_ requested: TimeInterval) {
            let t = min(requested, budgetLeft())
            if t > 0 { sleeper(t) }
        }

        func discover() -> Set<pid_t> {
            guard budgetLeft() > 0.05 else { return [] }
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

        // Run wineserver -k in parallel; each shares the remaining budget.
        let wineserverJobs: [(URL, String)] = targets.compactMap { prefix in
            let engine = engineForPrefix(prefix) ?? .defaultEngine
            guard let wineserver = PathManager.shared.wineserverExecutable(engine: engine) else {
                return nil
            }
            return (wineserver, prefix)
        }
        if !wineserverJobs.isEmpty, budgetLeft() > 0.05 {
            let perTimeout = min(
                options.wineserverKillTimeout,
                max(0.2, budgetLeft() / Double(wineserverJobs.count))
            )
            let group = DispatchGroup()
            for (wineserver, prefix) in wineserverJobs {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { group.leave() }
                    wineserverRunner(wineserver, prefix, perTimeout)
                }
            }
            _ = group.wait(timeout: .now() + budgetLeft())
        }

        // Bounded pause, then a second sweep for session-leader orphans that the
        // pre-kill tree/pgid snapshot missed (winetemp + mapped engines).
        sleepBudget(options.afterWineserverSeconds)
        if budgetLeft() > 0.05 {
            recorded.formUnion(discover())
        }

        for pid in recorded.sorted() {
            _ = signalSender(pid, SIGTERM)
        }
        sleepBudget(options.termGraceSeconds)

        if budgetLeft() > 0.05 {
            recorded.formUnion(discover())
        }
        for pid in recorded.sorted() {
            _ = signalSender(pid, SIGKILL)
        }
        sleepBudget(min(options.killGraceSeconds, budgetLeft()))
        guard budgetLeft() > 0.05 else { return [] }
        return discover().sorted()
    }

    /// `wineserver -k` with a hard timeout — never block quit for tens of seconds.
    public static func runWineserverKill(
        wineserver: URL,
        prefix: String,
        timeout: TimeInterval
    ) {
        guard timeout > 0.05 else { return }
        let process = Process()
        process.executableURL = wineserver
        process.arguments = ["-k"]
        process.environment = ["WINEPREFIX": prefix]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        _ = ProcessWait.waitUntilExit(process, timeout: timeout, escalateGrace: 0.2)
    }
}
