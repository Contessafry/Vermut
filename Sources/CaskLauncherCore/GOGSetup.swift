import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Inno `/VERYSILENT` still launches Galaxy after the files are on disk.
/// That child (with or without `/firstRun`) keeps `setup_galaxy.exe` from
/// exiting, so a wall-clock timeout fires on a completed install.
public enum GOGInstallAcceptance {
    /// Hung setup + payload on disk is success. Do not raise the 15-minute cap.
    public static func acceptInstallerResult(timedOut: Bool, payloadInstalled: Bool) -> Bool {
        if payloadInstalled { return true }
        return !timedOut
    }

    /// `nil` means the install succeeded (including a hung Inno after Galaxy landed).
    public static func wineError(
        timedOut: Bool,
        payloadInstalled: Bool,
        store: GameStore
    ) -> WineError? {
        if acceptInstallerResult(timedOut: timedOut, payloadInstalled: payloadInstalled) {
            return nil
        }
        return timedOut ? .installerTimedOut(store) : nil
    }
}

public enum GOGSetupWatch {
    /// Time to let Inno exit after Galaxy leftovers are gone.
    public static let postPayloadGrace: TimeInterval = 10

    public enum Decision: Equatable, Sendable {
        case wait
        case stopLeftovers
        case finishBecausePayloadInstalled
    }

    public static func decide(
        payloadInstalled: Bool,
        installerRunning: Bool,
        secondsSincePayloadSeen: TimeInterval?,
        leftoverCount: Int
    ) -> Decision {
        guard payloadInstalled else { return .wait }
        if leftoverCount > 0 { return .stopLeftovers }
        if installerRunning {
            if let seconds = secondsSincePayloadSeen, seconds >= postPayloadGrace {
                return .finishBecausePayloadInstalled
            }
            return .wait
        }
        return .finishBecausePayloadInstalled
    }
}

/// Any `GalaxyClient.exe` in this prefix — post-install `[Run]` often omits `/firstRun`.
public enum GOGSetupLeftovers {
    public static func pids(in psLines: [String], prefixPath: String) -> [pid_t] {
        psLines.compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.localizedCaseInsensitiveContains("GalaxyClient.exe"),
                  line.contains("WINEPREFIX=\(prefixPath)") else { return nil }
            return line.split(separator: " ", maxSplits: 1).first.flatMap { pid_t($0) }
        }
    }
}
