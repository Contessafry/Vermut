import AppKit
import CoreGraphics
import CaskLauncherCore

/// Best-effort close of Wine crash / "serious problem" dialogs between find-configuration attempts.
enum WineDialogDismisser {
    /// Typical Wine MessageBox / crash dialog — larger than a 1px flicker, smaller than a game view.
    static let dialogMinWidth: CGFloat = 180
    static let dialogMaxWidth: CGFloat = 640
    static let dialogMinHeight: CGFloat = 120
    static let dialogMaxHeight: CGFloat = 280

    @discardableResult
    static func dismissVisibleDialogs(winePIDs: Set<pid_t>? = nil) -> Int {
        let pids = winePIDs ?? SteamWindowWatcher.steamWinePIDs()
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return 0 }

        var dismissed = 0
        var seen = Set<pid_t>()
        for window in list {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  pids.contains(pid),
                  seen.insert(pid).inserted,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }
            let width = bounds["Width"] ?? 0
            let height = bounds["Height"] ?? 0
            guard width >= dialogMinWidth, width <= dialogMaxWidth,
                  height >= dialogMinHeight, height <= dialogMaxHeight
            else { continue }
            SteamWindowWatcher.bringToFront(pid: pid)
            postReturnKey()
            dismissed += 1
        }
        return dismissed
    }

    /// A game-sized window owned by one of the given PIDs (not a Wine alert).
    static func hasRealGameWindow(
        ownedBy pids: Set<pid_t>,
        minWidth: CGFloat = 400,
        minHeight: CGFloat = 300
    ) -> Bool {
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]]
        else { return false }
        for window in list {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  pids.contains(pid),
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }
            let width = bounds["Width"] ?? 0
            let height = bounds["Height"] ?? 0
            if width >= minWidth, height >= minHeight {
                return true
            }
        }
        return false
    }

    private static func postReturnKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
