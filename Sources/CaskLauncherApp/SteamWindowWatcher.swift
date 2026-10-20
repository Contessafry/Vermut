import AppKit
import Darwin
import CoreGraphics
import CaskLauncherCore

/// Reads Steam's first-run signals off the main thread and brings Wine windows forward.
enum SteamWindowWatcher {
    struct Snapshot {
        var inputs: SteamSetupInputs
        var logSize: Int
        var windowPID: pid_t?
    }

    static func bootstrapLogURL(prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/logs/bootstrap_log.txt")
    }

    static func snapshot(prefix: URL) -> Snapshot {
        let logURL = bootstrapLogURL(prefix: prefix)
        var bootstrap: SteamBootstrapState?
        var age: TimeInterval?
        var size = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path) {
            size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            if let m = attrs[.modificationDate] as? Date { age = Date().timeIntervalSince(m) }
            if let text = tail(of: logURL, bytes: 256 * 1024) { bootstrap = SteamBootstrapLog.parse(text) }
        }
        let helper = PrefixRuntime.processArgumentLines().contains(where: SteamSetupEvaluator.isBottleWebhelper)
        let pids = steamWinePIDs()
        let pid = wineWindowPID(winePIDs: pids)
        // Login/main window, not Steam's small "Updating Steam" progress box.
        let bigWindow = wineWindowPID(minWidth: 600, minHeight: 400, winePIDs: pids) != nil
        let inputs = SteamSetupInputs(
            bootstrap: bootstrap,
            secondsSinceLogChange: age,
            clientFilesReady: SteamReadiness.isClientReady(inPrefix: prefix),
            webhelperRunning: helper,
            windowVisible: bigWindow
        )
        return Snapshot(inputs: inputs, logSize: size, windowPID: pid)
    }

    static func tail(of url: URL, bytes: Int) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: end > UInt64(bytes) ? end - UInt64(bytes) : 0)
        guard let data = try? h.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// A normal-layer on-screen window owned by a Wine process running Steam from a
    /// Windows path (owner name and executable vary: "wine", "Steam" in a winetemp
    /// bundle, ...). Native Steam runs from Unix paths and never matches.
    /// Uses owner pid/bounds only (no titles), so no Screen Recording needed.
    static func wineWindowPID(minWidth: CGFloat = 300, minHeight: CGFloat = 200, winePIDs: Set<pid_t>? = nil) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let pids = winePIDs ?? steamWinePIDs()
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) >= minWidth, (b["Height"] ?? 0) >= minHeight,
                  pids.contains(pid) else { continue }
            return pid
        }
        return nil
    }

    /// PIDs of Wine processes whose command is a Windows Steam path.
    static func steamWinePIDs() -> Set<pid_t> {
        var out = Set<pid_t>()
        for line in PrefixRuntime.processPIDLines() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let sp = t.firstIndex(of: " "), let pid = pid_t(t[..<sp]) else { continue }
            let cmd = t[sp...].trimmingCharacters(in: .whitespaces)
            if SteamSetupEvaluator.isBottleSteamCommand(cmd) { out.insert(pid) }
        }
        return out
    }

    @MainActor
    static func bringToFront(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: app)
            app.activate(options: [.activateAllWindows])
        } else {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }
}
