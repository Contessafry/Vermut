import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Bounded log file. Every byte Vermut or a child process (Wine, Steam, GOG,
/// Legendary) writes to a store log goes through here, so no log can grow
/// without limit:
/// - when the file reaches `maxBytes` it is rotated to `<name>.1.<ext>`
///   (one old file kept, the previous one dropped);
/// - identical consecutive lines are collapsed after `repeatThreshold`
///   occurrences into a single "repeated N times" note (Wine error loops).
public final class CappedLogWriter: @unchecked Sendable {
    public static let defaultMaxBytes: UInt64 = 10 * 1024 * 1024
    public static let repeatThreshold = 3
    /// Write a summary at least this often while a line keeps repeating.
    public static let repeatSummaryEvery = 100_000

    public let url: URL
    public let maxBytes: UInt64
    private let lock = NSLock()
    private var handle: FileHandle?
    private var size: UInt64 = 0
    private var pending = Data()
    private var lastLine: String?
    private var repeatCount = 0
    private var suppressed = 0

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: CappedLogWriter] = [:]

    /// One writer per path, so Vermut's own lines and a child's output share the cap.
    public static func shared(for url: URL, maxBytes: UInt64 = defaultMaxBytes) -> CappedLogWriter {
        registryLock.lock(); defer { registryLock.unlock() }
        if let w = registry[url.path] { return w }
        let w = CappedLogWriter(url: url, maxBytes: maxBytes)
        registry[url.path] = w
        return w
    }

    public init(url: URL, maxBytes: UInt64 = defaultMaxBytes) {
        self.url = url
        self.maxBytes = maxBytes
    }

    public static func rotatedURL(for url: URL) -> URL {
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let name = ext.isEmpty ? base + ".1" : base + ".1." + ext
        return url.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Append one line (no trailing newline needed).
    public func append(line: String) {
        lock.lock(); defer { lock.unlock() }
        appendLocked(line)
    }

    /// Feed raw child output; complete lines are written, a partial tail is kept.
    public func consume(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        while let nl = pending.firstIndex(of: 0x0A) {
            let lineData = pending.subdata(in: pending.startIndex..<nl)
            pending.removeSubrange(pending.startIndex...nl)
            appendLocked(String(decoding: lineData, as: UTF8.self))
        }
        // A child that never writes a newline must not grow memory either.
        if pending.count > 64 * 1024 {
            appendLocked(String(decoding: pending, as: UTF8.self))
            pending.removeAll()
        }
    }

    /// Write any partial line and pending repeat summary.
    public func flush() {
        lock.lock(); defer { lock.unlock() }
        if !pending.isEmpty {
            appendLocked(String(decoding: pending, as: UTF8.self))
            pending.removeAll()
        }
        emitSuppressedSummary()
        try? handle?.synchronize()
    }

    /// Drain a pipe's read end on a background thread until EOF.
    public func pump(readFD fd: Int32) {
        let thread = Thread { [self] in
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                if n > 0 {
                    consume(Data(buffer[0..<n]))
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
            close(fd)
            flush()
        }
        thread.name = "vermut.log." + url.lastPathComponent
        thread.start()
    }

    /// Pipe-backed handle for a Foundation `Process` (stdout and/or stderr).
    public func makeProcessPipe() -> Pipe {
        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                self?.flush()
            } else {
                self?.consume(data)
            }
        }
        return pipe
    }

    // MARK: - Private (lock held)

    private func appendLocked(_ line: String) {
        if line == lastLine {
            repeatCount += 1
            if repeatCount > Self.repeatThreshold {
                suppressed += 1
                if suppressed >= Self.repeatSummaryEvery { emitSuppressedSummary() }
                return
            }
        } else {
            emitSuppressedSummary()
            lastLine = line
            repeatCount = 1
        }
        writeLocked(line + "\n")
    }

    private func emitSuppressedSummary() {
        guard suppressed > 0 else { return }
        let n = suppressed
        suppressed = 0
        writeLocked("Vermut: previous line repeated \(n) more times\n")
    }

    private func writeLocked(_ text: String) {
        let data = Data(text.utf8)
        openIfNeeded()
        if size + UInt64(data.count) > maxBytes {
            rotateLocked()
        }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            size += UInt64(data.count)
        } catch {}
    }

    private func openIfNeeded() {
        guard handle == nil else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        size = (try? handle?.seekToEnd()) ?? 0
        if size >= maxBytes { rotateLocked() }
    }

    private func rotateLocked() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        let old = Self.rotatedURL(for: url)
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: url, to: old)
        fm.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        size = 0
    }
}
