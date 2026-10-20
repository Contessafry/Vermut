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
        let pid = wineWindowPID()
        // Login/main window, not Steam's small "Updating Steam" progress box.
        let bigWindow = wineWindowPID(minWidth: 600, minHeight: 400) != nil
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

    /// A normal-layer on-screen window owned by a process running Vermut's own Wine
    /// (owner name varies: "wine", "Steam", ...; native Steam is excluded by path).
    /// Uses owner pid/bounds only (no titles), so no Screen Recording needed.
    static func wineWindowPID(minWidth: CGFloat = 300, minHeight: CGFloat = 200) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let enginesRoot = PathManager.shared.appSupportURL.path
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) >= minWidth, (b["Height"] ?? 0) >= minHeight,
                  isVermutWine(pid: pid, root: enginesRoot) else { continue }
            return pid
        }
        return nil
    }

    static func isVermutWine(pid: pid_t, root: String) -> Bool {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return false }
        let path = String(cString: buf)
        return path.hasPrefix(root) && path.lowercased().contains("wine")
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
