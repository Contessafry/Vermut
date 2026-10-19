import XCTest
@testable import CaskLauncherCore

final class LogTailTests: XCTestCase {
    func testLargeLogOnlyReturnsTheTail() throws {
        let url = try writeLog(lineCount: 32_018, prefix: "line")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let size = try fileSize(url)
        XCTAssertGreaterThan(size, LogTail.defaultMaxBytes, "fixture must exceed the 512 KB cap")

        let started = Date()
        let snap = LogTail.read(from: url)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0, "tail read should not scan the whole file on the caller")

        XCTAssertLessThanOrEqual(snap.lines.count, LogTail.defaultMaxLines)
        XCTAssertEqual(snap.lines.count, LogTail.defaultMaxLines)
        XCTAssertTrue(snap.truncated)
        XCTAssertEqual(snap.fileSize, size)
        XCTAssertEqual(snap.lines.last, "line-32018 wine: some log output for steam")
        XCTAssertEqual(snap.lines.first, "line-30019 wine: some log output for steam")
        XCTAssertFalse(snap.lines.contains(where: { $0.hasPrefix("line-1 ") }))
        XCTAssertFalse(snap.text.contains("line-1 wine:"))
        XCTAssertLessThanOrEqual(snap.byteLength, LogTail.defaultMaxBytes)
    }

    func testByteCapAppliesBeforeLineCap() throws {
        let url = try writeLog(lineCount: 40, prefix: "row", pad: 20_000)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let snap = LogTail.read(from: url, maxBytes: 64 * 1024, maxLines: 2_000)
        XCTAssertTrue(snap.truncated)
        XCTAssertLessThan(snap.lines.count, 40)
        XCTAssertEqual(snap.lines.last?.hasPrefix("row-40 "), true)
        XCTAssertFalse(snap.lines.contains(where: { $0.hasPrefix("row-1 ") }))
    }

    func testSmallLogIsNotTruncated() throws {
        let url = try writeLog(lineCount: 12, prefix: "ok")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let snap = LogTail.read(from: url)
        XCTAssertFalse(snap.truncated)
        XCTAssertEqual(snap.lines.count, 12)
        XCTAssertEqual(snap.lines.first, "ok-1 wine: some log output for steam")
        XCTAssertEqual(snap.lines.last, "ok-12 wine: some log output for steam")
    }

    func testMissingLogIsEmpty() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-missing-\(UUID().uuidString).log")
        let snap = LogTail.read(from: url)
        XCTAssertEqual(snap, .empty)
        XCTAssertTrue(snap.lines.isEmpty)
        XCTAssertFalse(snap.truncated)
    }

    func testFingerprintChangesAfterAppend() throws {
        let url = try writeLog(lineCount: 3, prefix: "fp")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let before = LogTail.fingerprint(at: url)
        XCTAssertFalse(LogTail.shouldReload(previous: before, current: before))

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        _ = handle.seekToEndOfFile()
        handle.write(Data("fp-4 extra\n".utf8))

        let after = LogTail.fingerprint(at: url)
        XCTAssertTrue(LogTail.shouldReload(previous: before, current: after))
        XCTAssertGreaterThan(after.size, before.size)
    }

    func testPollIntervalIsThrottled() {
        XCTAssertGreaterThanOrEqual(LogTail.defaultPollIntervalNanoseconds, 250_000_000)
        XCTAssertLessThanOrEqual(LogTail.defaultPollIntervalNanoseconds, 1_000_000_000)
    }

    func testEmptyExistingFile() throws {
        let dir = try scratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("empty.log")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        let snap = LogTail.read(from: url)
        XCTAssertTrue(snap.lines.isEmpty)
        XCTAssertFalse(snap.truncated)
        XCTAssertEqual(snap.fileSize, 0)
    }

    private func writeLog(lineCount: Int, prefix: String, pad: Int = 0) throws -> URL {
        let dir = try scratchDir()
        let url = dir.appendingPathComponent("steam.log")
        var data = Data()
        data.reserveCapacity(max(lineCount * 48, pad * lineCount))
        let padding = pad > 0 ? String(repeating: "z", count: pad) : "wine: some log output for steam"
        for i in 1...lineCount {
            data.append(contentsOf: "\(prefix)-\(i) \(padding)\n".utf8)
        }
        try data.write(to: url)
        return url
    }

    private func scratchDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-logtail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileSize(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.intValue ?? 0
    }
}
