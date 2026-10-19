import XCTest
@testable import CaskLauncherCore

final class ProcessPipeTests: XCTestCase {

    /// A child that writes more than the kernel pipe buffer (~64 KiB) deadlocks
    /// if the parent `waitUntilExit()`s before draining stdout.
    func testLargeStdoutIsDrainedBeforeWait() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "dd if=/dev/zero bs=1024 count=256 2>/dev/null"]

        let finished = expectation(description: "drain 256 KiB without deadlock")
        let box = StdoutBox()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                box.data = try ProcessPipe.runReadingStdout(process)
            } catch {
                box.error = error
            }
            finished.fulfill()
        }

        wait(for: [finished], timeout: 8)
        XCTAssertNil(box.error)
        XCTAssertGreaterThanOrEqual(box.data.count, 256 * 1024)
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testProcessArgumentLinesReturnsWithoutDeadlock() {
        let lines = PrefixRuntime.processArgumentLines()
        XCTAssertFalse(lines.isEmpty, "ps should list at least this test process")
    }

    func testWaitUntilExitTimesOutInsteadOfHanging() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["8"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let started = Date()
        let result = ProcessWait.waitUntilExit(process, timeout: 0.4)
        XCTAssertEqual(result, .timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertFalse(process.isRunning)
    }

    func testWaitUntilExitNilTimeoutMatchesProcessExit() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["true"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let result = ProcessWait.waitUntilExit(process, timeout: nil)
        XCTAssertEqual(result, .exited(0))
    }
}

/// `@unchecked Sendable` box so the drain runs off the test thread (deadlock
/// would then trip the expectation timeout instead of hanging XCTest forever).
private final class StdoutBox: @unchecked Sendable {
    var data = Data()
    var error: Error?
}
