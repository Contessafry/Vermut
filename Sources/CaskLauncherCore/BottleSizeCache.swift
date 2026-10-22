import Foundation

/// On-demand directory size with a simple TTL cache (beta default for open Q3).
public final class BottleSizeCache: @unchecked Sendable {
    public static let shared = BottleSizeCache()

    public var timeToLive: TimeInterval = 60

    private struct Entry {
        var bytes: Int64
        var computedAt: Date
    }

    private let lock = NSLock()
    private var entries: [URL: Entry] = [:]
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func size(of url: URL, now: Date = Date(), force: Bool = false) -> Int64 {
        lock.lock()
        if !force, let entry = entries[url], now.timeIntervalSince(entry.computedAt) < timeToLive {
            let bytes = entry.bytes
            lock.unlock()
            return bytes
        }
        lock.unlock()

        let bytes = Self.directorySize(at: url, fileManager: fileManager)
        lock.lock()
        entries[url] = Entry(bytes: bytes, computedAt: now)
        lock.unlock()
        return bytes
    }

    public func invalidate(_ url: URL) {
        lock.lock()
        entries.removeValue(forKey: url)
        lock.unlock()
    }

    public func invalidateAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    public static func directorySize(at url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
