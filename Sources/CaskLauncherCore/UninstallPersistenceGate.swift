import Foundation

/// Process-wide latch: once an uninstall wipe starts, Vermut must not recreate
/// `Application Support/Vermut` trees or rewrite `config.json`.
public enum UninstallPersistenceGate: Sendable {
    private static let lock = NSLock()
    private static var _writesSuppressed = false

    /// True after `beginWipe()` — ConfigurationManager / PathManager honor this.
    public static var writesSuppressed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _writesSuppressed
    }

    /// Call before trashing App Support. Idempotent; never clears for the process lifetime.
    public static func beginWipe() {
        lock.lock()
        _writesSuppressed = true
        lock.unlock()
    }

    /// Test-only reset.
    public static func resetForTests() {
        lock.lock()
        _writesSuppressed = false
        lock.unlock()
    }
}
