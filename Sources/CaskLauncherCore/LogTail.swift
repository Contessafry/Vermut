import Foundation

/// Last chunk of a bottle log, capped so the UI never loads a multi-megabyte file.
public struct LogTailSnapshot: Equatable, Sendable {
    public var lines: [String]
    public var truncated: Bool
    public var byteLength: Int
    public var fileSize: Int
    public var modificationDate: Date?

    public init(
        lines: [String],
        truncated: Bool,
        byteLength: Int,
        fileSize: Int,
        modificationDate: Date?
    ) {
        self.lines = lines
        self.truncated = truncated
        self.byteLength = byteLength
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }

    public var text: String {
        lines.joined(separator: "\n")
    }

    public static let empty = LogTailSnapshot(
        lines: [],
        truncated: false,
        byteLength: 0,
        fileSize: 0,
        modificationDate: nil
    )
}

public struct LogTailFingerprint: Equatable, Sendable {
    public var size: Int
    public var modificationDate: Date?

    public init(size: Int, modificationDate: Date?) {
        self.size = size
        self.modificationDate = modificationDate
    }
}

/// Reads only the tail of a log file. Safe to call off the main thread.
public enum LogTail {
    public static let defaultMaxBytes = 512 * 1024
    public static let defaultMaxLines = 2_000
    /// Live-tail poll interval. Keeps UI updates off a tight I/O loop.
    public static let defaultPollIntervalNanoseconds: UInt64 = 400_000_000

    public static func fingerprint(at url: URL) -> LogTailFingerprint {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return LogTailFingerprint(size: 0, modificationDate: nil)
        }
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        return LogTailFingerprint(
            size: size,
            modificationDate: attrs[.modificationDate] as? Date
        )
    }

    public static func shouldReload(previous: LogTailFingerprint, current: LogTailFingerprint) -> Bool {
        previous != current
    }

    public static func read(
        from url: URL,
        maxBytes: Int = defaultMaxBytes,
        maxLines: Int = defaultMaxLines
    ) -> LogTailSnapshot {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return .empty
        }
        let fingerprint = fingerprint(at: url)
        let fileSize = fingerprint.size
        let mtime = fingerprint.modificationDate
        if fileSize <= 0 {
            return LogTailSnapshot(
                lines: [],
                truncated: false,
                byteLength: 0,
                fileSize: 0,
                modificationDate: mtime
            )
        }

        let maxBytes = max(1, maxBytes)
        let maxLines = max(1, maxLines)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return LogTailSnapshot(
                lines: [],
                truncated: false,
                byteLength: 0,
                fileSize: fileSize,
                modificationDate: mtime
            )
        }
        defer { try? handle.close() }

        let startedMidFile = fileSize > maxBytes
        if startedMidFile {
            let offset = UInt64(fileSize - maxBytes)
            do {
                try handle.seek(toOffset: offset)
            } catch {
                return LogTailSnapshot(
                    lines: [],
                    truncated: true,
                    byteLength: 0,
                    fileSize: fileSize,
                    modificationDate: mtime
                )
            }
        }

        let data = readRemaining(handle)
        var text = decodeUTF8(data, skipLeadingPartial: startedMidFile)
        if startedMidFile, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }

        var truncated = startedMidFile
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
            truncated = true
        }

        return LogTailSnapshot(
            lines: lines,
            truncated: truncated,
            byteLength: data.count,
            fileSize: fileSize,
            modificationDate: mtime
        )
    }

    private static func readRemaining(_ handle: FileHandle) -> Data {
        if let data = try? handle.readToEnd() {
            return data
        }
        var data = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data
    }

    private static func decodeUTF8(_ data: Data, skipLeadingPartial: Bool) -> String {
        if !skipLeadingPartial, let exact = String(data: data, encoding: .utf8) {
            return exact
        }
        var slice = data
        if skipLeadingPartial {
            var skipped = 0
            while skipped < 4, !slice.isEmpty {
                if let exact = String(data: slice, encoding: .utf8) {
                    return exact
                }
                slice = slice.dropFirst()
                skipped += 1
            }
        }
        return String(decoding: slice, as: UTF8.self)
    }
}
