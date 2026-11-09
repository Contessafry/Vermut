import Foundation

/// Result of a cheap Rosetta 2 probe. Intel Macs never need it.
public enum RosettaCheckDecision: Equatable, Sendable {
    case notRequired
    case present
    case missing

    public var shouldShowInstallBanner: Bool { self == .missing }

    /// True when games can run without a Rosetta install prompt (Intel, or Apple Silicon with a working translator).
    public var isUsable: Bool { self != .missing }
}

/// Runs the x86_64 translation smoke test (`arch -x86_64 /usr/bin/true`).
public protocol RosettaCommandRunning: Sendable {
    func probeX86Translation() -> Bool
}

public struct ProcessRosettaCommandRunner: RosettaCommandRunning {
    public init() {}

    public func probeX86Translation() -> Bool {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}

public enum RosettaCheck {
    public static func decide(isAppleSilicon: Bool, probeSucceeded: Bool) -> RosettaCheckDecision {
        guard isAppleSilicon else { return .notRequired }
        return probeSucceeded ? .present : .missing
    }

    public static func evaluate(
        isAppleSilicon: Bool,
        runner: any RosettaCommandRunning
    ) -> RosettaCheckDecision {
        decide(
            isAppleSilicon: isAppleSilicon,
            probeSucceeded: runner.probeX86Translation()
        )
    }
}
