import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Shared stdout drain for `Foundation.Process`.
///
/// A kernel pipe is small (~64 KiB). If the parent `waitUntilExit()`s before
/// reading, a chatty child (`ps -axEww` with Wine running) fills the pipe,
/// blocks on write, and never exits — the UI deadlocks on the main actor.
enum ProcessPipe {
    /// Attach stdout to a pipe, run, drain to EOF, *then* wait.
    static func runReadingStdout(_ process: Process) throws -> Data {
        let pipe = Pipe()
        process.standardOutput = pipe
        if process.standardError == nil {
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        let data = readToEnd(pipe.fileHandleForReading)
        process.waitUntilExit()
        return data
    }

    /// Drain `handle` until EOF. Prefer this over `waitUntilExit` first.
    /// `availableData` is empty at EOF; `readDataToEndOfFile` is equivalent
    /// when it actually loops to EOF, but is easy to call in the wrong order.
    static func readToEnd(_ handle: FileHandle) -> Data {
        var data = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data
    }
}

enum ProcessWait {
    enum Result: Equatable, Sendable {
        case exited(Int32)
        case timedOut
    }

    /// `timeout == nil` waits forever (Steam). Otherwise SIGTERM, then SIGKILL.
    /// `escalateGrace` is how long to wait after SIGTERM before SIGKILL (keep short on quit).
    static func waitUntilExit(
        _ process: Process,
        timeout: TimeInterval?,
        escalateGrace: TimeInterval = 5
    ) -> Result {
        guard let timeout else {
            process.waitUntilExit()
            return .exited(process.terminationStatus)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                let grace = Date().addingTimeInterval(max(0, escalateGrace))
                while process.isRunning, Date() < grace {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    Thread.sleep(forTimeInterval: 0.05)
                }
                return .timedOut
            }
            Thread.sleep(forTimeInterval: min(0.1, max(0.01, timeout / 20)))
        }
        return .exited(process.terminationStatus)
    }
}
