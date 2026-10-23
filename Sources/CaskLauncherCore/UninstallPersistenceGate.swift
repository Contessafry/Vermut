import Foundation

/// Process-wide latches for uninstall wipe + post-Done quit.
///
/// Does **not** depend on `AppState` / the app delegate's weak ref — Mac QA showed
/// `NSApp.terminate` + `.terminateNow` leaving the PID alive after data wipe.
public enum UninstallPersistenceGate: Sendable {
    private static let lock = NSLock()
    private static var _writesSuppressed = false
    private static var _immediateExitArmed = false

    /// True after `beginWipe()` — ConfigurationManager / PathManager honor this.
    public static var writesSuppressed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _writesSuppressed
    }

    /// True after Done-screen Quit is armed (or wipe prepared). Quit must exit the process.
    public static var immediateExitArmed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _immediateExitArmed
    }

    /// Call before trashing App Support. Idempotent for the process lifetime.
    public static func beginWipe() {
        lock.lock()
        _writesSuppressed = true
        lock.unlock()
    }

    /// Call from Done → Quit Vermut (and optionally when wipe starts).
    /// Decouples quit from `VermutAppDelegate.appState` weak reference.
    public static func armImmediateExit() {
        lock.lock()
        _writesSuppressed = true
        _immediateExitArmed = true
        lock.unlock()
    }

    /// Whether quit should skip Wine cleanup and hard-exit (post-wipe Done / armed Quit).
    public static var shouldSkipWineCleanupAndExit: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _immediateExitArmed || _writesSuppressed
    }

    /// Test-only reset.
    public static func resetForTests() {
        lock.lock()
        _writesSuppressed = false
        _immediateExitArmed = false
        lock.unlock()
    }
}
