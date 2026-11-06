import Foundation

/// Snapshot the runner feeds into the success heuristic (no Wine / AppKit).
public struct FindConfigurationObservation: Sendable, Equatable {
    public var processAlive: Bool
    public var aliveSeconds: TimeInterval
    public var hasRealWindow: Bool
    public var logText: String

    public init(
        processAlive: Bool,
        aliveSeconds: TimeInterval,
        hasRealWindow: Bool,
        logText: String
    ) {
        self.processAlive = processAlive
        self.aliveSeconds = aliveSeconds
        self.hasRealWindow = hasRealWindow
        self.logText = logText
    }
}

public enum FindConfigurationVerdict: Sendable, Equatable {
    case keepWaiting
    case failed(String)
    case candidate

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Pure success / failure rules for one find-configuration attempt.
public enum FindConfigurationSuccess {
    /// Markers that mean the title died in graphics / player init (black screen still possible without these).
    public static let fatalMarkers: [String] = [
        "InitializeEngineGraphics failed",
        "Failed to initialize player",
        "Failed to initialize the player",
        "Failed to create D3D11 device",
        "DXGI_ERROR_UNSUPPORTED",
        "err:d3d:wined3d_adapter",
        "wine: Unhandled page fault",
        "err:seh:start_debugger"
    ]

    public static func evaluate(
        _ observation: FindConfigurationObservation,
        threshold: TimeInterval = FindConfigurationSettings.default.aliveThreshold
    ) -> FindConfigurationVerdict {
        let clamped = FindConfigurationSettings.clampThreshold(threshold)
        if let marker = firstFatalMarker(in: observation.logText) {
            return .failed("Fatal log marker: \(marker)")
        }
        if !observation.processAlive, observation.aliveSeconds < clamped {
            return .failed("Game process exited after \(Int(observation.aliveSeconds))s")
        }
        if !observation.processAlive {
            return .failed("Game process is not running")
        }
        if observation.aliveSeconds >= clamped, observation.hasRealWindow {
            return .candidate
        }
        return .keepWaiting
    }

    public static func firstFatalMarker(in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        for marker in fatalMarkers {
            if text.range(of: marker, options: .caseInsensitive) != nil {
                return marker
            }
        }
        return nil
    }

    public static func containsFatalMarker(_ text: String) -> Bool {
        firstFatalMarker(in: text) != nil
    }
}
