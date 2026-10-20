import Foundation

/// Stages Steam goes through after SteamSetup, up to a usable client.
public enum SteamSetupStage: Equatable, Sendable {
    case firstStart                    // steam.exe started, no update activity yet
    case updating(progress: Double?)   // bootstrapper checking/downloading the client
    case finishing                     // update done, waiting for steamwebhelper + window
    case ready

    public var label: String {
        switch self {
        case .firstStart: return "Starting Steam for the first time…"
        case .updating(let p?):
            return "Updating Steam… \(Int((p * 100).rounded()))%"
        case .updating(nil): return "Updating Steam…"
        case .finishing: return "Finishing Steam setup…"
        case .ready: return "Ready"
        }
    }
}

/// What Steam's `logs/bootstrap_log.txt` says about the client update.
public struct SteamBootstrapState: Equatable, Sendable {
    public var sawUpdateActivity: Bool
    public var updateInProgress: Bool
    public var updateCompleted: Bool
    public var progress: Double?
}

public enum SteamBootstrapLog {
    /// Parses the tail of bootstrap_log.txt. Only the order of events matters:
    /// any check/download after the last "Download complete." means an update
    /// is (again) in progress.
    public static func parse(_ text: String) -> SteamBootstrapState {
        var state = SteamBootstrapState(sawUpdateActivity: false, updateInProgress: false, updateCompleted: false, progress: nil)
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.contains("Downloading update (") {
                state.sawUpdateActivity = true
                state.updateInProgress = true
                state.updateCompleted = false
                state.progress = downloadFraction(line) ?? state.progress
            } else if line.contains("Checking for available update")
                        || line.contains("Downloading manifest")
                        || line.contains("Add pending download")
                        || line.contains("Extracting package")
                        || line.contains("Installing update") {
                state.sawUpdateActivity = true
                state.updateInProgress = true
                state.updateCompleted = false
            } else if line.contains("Download complete.") || line.contains("Update complete") {
                state.sawUpdateActivity = true
                state.updateInProgress = false
                state.updateCompleted = true
                state.progress = 1
            } else if (line.contains("Package file") && line.contains("up to date"))
                        || line.contains("Nothing to do")
                        || line.contains("Download skipped") {
                state.updateInProgress = false
                state.updateCompleted = true
            }
        }
        return state
    }

    /// "Downloading update (165,627 of 238,534 KB)..." -> 0.694
    static func downloadFraction(_ line: String) -> Double? {
        guard let open = line.range(of: "Downloading update ("),
              let close = line.range(of: " KB)", range: open.upperBound..<line.endIndex) else { return nil }
        let inner = line[open.upperBound..<close.lowerBound].replacingOccurrences(of: ",", with: "")
        let parts = inner.components(separatedBy: " of ")
        guard parts.count == 2, let done = Double(parts[0]), let total = Double(parts[1]), total > 0 else { return nil }
        return min(max(done / total, 0), 1)
    }
}

public struct SteamSetupInputs: Equatable, Sendable {
    public var bootstrap: SteamBootstrapState?
    /// Seconds since bootstrap_log.txt last changed (nil if absent).
    public var secondsSinceLogChange: TimeInterval?
    public var clientFilesReady: Bool
    public var webhelperRunning: Bool
    public var windowVisible: Bool

    public init(bootstrap: SteamBootstrapState?, secondsSinceLogChange: TimeInterval?, clientFilesReady: Bool, webhelperRunning: Bool, windowVisible: Bool) {
        self.bootstrap = bootstrap
        self.secondsSinceLogChange = secondsSinceLogChange
        self.clientFilesReady = clientFilesReady
        self.webhelperRunning = webhelperRunning
        self.windowVisible = windowVisible
    }
}

public enum SteamSetupEvaluator {
    /// No bootstrap-log activity for this long before Ready.
    public static let quietSeconds: TimeInterval = 10
    /// No visible progress for this long shows a neutral "Still working…" + Retry.
    public static let stallSeconds: TimeInterval = 180

    public static func stage(_ i: SteamSetupInputs) -> SteamSetupStage {
        let b = i.bootstrap
        if let b, b.updateInProgress { return .updating(progress: b.progress) }
        let updateDone = (b?.updateCompleted ?? false) || i.clientFilesReady
        guard updateDone else {
            return (b?.sawUpdateActivity ?? false) ? .updating(progress: b?.progress) : .firstStart
        }
        let quiet = (i.secondsSinceLogChange ?? .infinity) >= quietSeconds
        if quiet && i.webhelperRunning && i.windowVisible && i.clientFilesReady { return .ready }
        return .finishing
    }

    /// True when neither the stage nor the log changed for `stallSeconds`.
    public static func isStalled(secondsSinceProgress: TimeInterval) -> Bool {
        secondsSinceProgress >= stallSeconds
    }

    /// A Wine process command line running Steam from the bottle (Windows path).
    public static func isBottleSteamCommand(_ command: String) -> Bool {
        let c = command.lowercased()
        return c.hasPrefix("c:\\") && c.contains("\\steam\\")
    }

    /// A ps line for the bottle's CEF helper (not native Steam's Mac helper).
    public static func isBottleWebhelper(_ psLine: String) -> Bool {
        psLine.lowercased().contains("steamwebhelper.exe")
    }
}
