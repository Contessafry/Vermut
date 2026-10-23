import Foundation

/// Gcenx Wine staging/devel builds expect a system GStreamer.framework.
/// Missing GStreamer must not block download or launch — only warn.
public struct GStreamerStatus: Equatable, Sendable {
    public var isPresent: Bool
    public var frameworkURL: URL?
    public var userFacingMessage: String?

    public init(isPresent: Bool, frameworkURL: URL? = nil, userFacingMessage: String? = nil) {
        self.isPresent = isPresent
        self.frameworkURL = frameworkURL
        self.userFacingMessage = userFacingMessage
    }
}

public enum GStreamerProbe {
    /// Common all-users / Homebrew / MacPorts locations for GStreamer.framework.
    public static let candidatePaths: [String] = [
        "/Library/Frameworks/GStreamer.framework",
        "/usr/local/opt/gstreamer/lib/GStreamer.framework",
        "/opt/homebrew/opt/gstreamer/lib/GStreamer.framework",
        "/opt/local/Library/Frameworks/GStreamer.framework"
    ]

    public static func probe(fileManager: FileManager = .default) -> GStreamerStatus {
        for path in candidatePaths {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                return GStreamerStatus(isPresent: true, frameworkURL: url)
            }
        }
        return GStreamerStatus(
            isPresent: false,
            userFacingMessage: missingMessage
        )
    }

    public static let missingMessage =
        "GStreamer.framework was not found. Gcenx Wine Staging/Devel may miss multimedia features until you install GStreamer for all users. Vermut will still download and run the engine."

    public static let installHint =
        "Install GStreamer from https://gstreamer.freedesktop.org/download/ (macOS framework, all users) or via Homebrew/MacPorts."
}
