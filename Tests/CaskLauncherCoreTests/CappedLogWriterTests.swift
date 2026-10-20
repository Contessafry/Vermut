import XCTest
@testable import CaskLauncherCore

final class CappedLogWriterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vermut-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func size(_ url: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.uint64Value ?? 0
    }

    func testCapIsEnforcedAndOneRotationKept() {
        let url = dir.appendingPathComponent("steam.log")
        let w = CappedLogWriter(url: url, maxBytes: 4_096)
        for i in 0..<5_000 { w.append(line: "distinct line number \(i)") }
        w.flush()
        let rotated = CappedLogWriter.rotatedURL(for: url)
        XCTAssertEqual(rotated.lastPathComponent, "steam.1.log")
        XCTAssertLessThanOrEqual(size(url), 4_096)
        XCTAssertLessThanOrEqual(size(rotated), 4_096)
        XCTAssertGreaterThan(size(rotated), 0)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertEqual(Set(files), ["steam.log", "steam.1.log"])
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        XCTAssertTrue(text.contains("distinct line number 4999"))
    }

    func testOversizedExistingLogIsRotatedOnOpen() throws {
        let url = dir.appendingPathComponent("gog.log")
        try Data(repeating: 0x41, count: 10_000).write(to: url)
        let w = CappedLogWriter(url: url, maxBytes: 4_096)
        w.append(line: "fresh")
        w.flush()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "fresh\n")
        XCTAssertEqual(size(CappedLogWriter.rotatedURL(for: url)), 10_000)
    }

    func testRepeatedLinesAreCollapsed() throws {
        let url = dir.appendingPathComponent("epic.log")
        let w = CappedLogWriter(url: url, maxBytes: 1_000_000)
        let loop = "0124:err:sync:server_register_wait Failed to send server register wait: 0x10000003"
        for _ in 0..<50_000 { w.consume(Data((loop + "\n").utf8)) }
        w.append(line: "after")
        w.flush()
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.filter { $0 == loop }.count, CappedLogWriter.repeatThreshold)
        XCTAssertTrue(lines.contains("Vermut: previous line repeated \(50_000 - CappedLogWriter.repeatThreshold) more times"))
        XCTAssertEqual(lines.last, "after")
    }

    func testPumpDrainsChildPipeWithinCap() throws {
        let url = dir.appendingPathComponent("child.log")
        let w = CappedLogWriter(url: url, maxBytes: 8_192)
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&fds), 0)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Bounded loop of varied lines; output only ever reaches the pipe.
        p.arguments = ["-c", "i=0; while [ $i -lt 3000 ]; do echo \"wine err $i\" >&2; i=$((i+1)); done"]
        p.standardError = FileHandle(fileDescriptor: fds[1], closeOnDealloc: false)
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        close(fds[1])
        w.pump(readFD: fds[0])
        p.waitUntilExit()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let t = try? String(contentsOf: url, encoding: .utf8), t.contains("wine err 2999") { break }
            usleep(20_000)
        }
        XCTAssertTrue((try? String(contentsOf: url, encoding: .utf8))?.contains("wine err 2999") ?? false)
        XCTAssertLessThanOrEqual(size(url), 8_192)
    }

    func testEpicWineDebugKeepsErrorsButNoFixmes() {
        // Epic keeps err output for compat reports; the cap + repeat collapse bound it.
        XCTAssertTrue(StoreLaunchRecipe.epicWineDebug.contains("fixme-all"))
    }
}
