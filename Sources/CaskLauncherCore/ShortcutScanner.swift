import Foundation

/// Discovers `.lnk` shortcuts under Start Menu and Desktop inside a Wine prefix.
public enum ShortcutScanner {
    public struct FoundShortcut: Equatable, Sendable {
        public var displayName: String
        public var windowsPath: String
        public var locationLabel: String

        public init(displayName: String, windowsPath: String, locationLabel: String) {
            self.displayName = displayName
            self.windowsPath = windowsPath
            self.locationLabel = locationLabel
        }
    }

    public static func scan(prefix: URL, fileManager: FileManager = .default) -> [FoundShortcut] {
        var results: [FoundShortcut] = []
        let roots: [(URL, String)] = [
            (
                prefix.appendingPathComponent("drive_c/ProgramData/Microsoft/Windows/Start Menu"),
                "Start Menu"
            ),
            (
                prefix.appendingPathComponent("drive_c/users"),
                "Desktop"
            )
        ]

        for (root, label) in roots {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                let name = fileURL.lastPathComponent
                guard name.lowercased().hasSuffix(".lnk") else { continue }
                if label == "Desktop", !fileURL.path.contains("/Desktop/") {
                    continue
                }
                let display = String(name.dropLast(4))
                let windowsPath = hostPathToWindows(fileURL, prefix: prefix)
                results.append(FoundShortcut(
                    displayName: display,
                    windowsPath: windowsPath,
                    locationLabel: label
                ))
            }
        }
        return results
    }

    /// Best-effort host path → `C:\…` for display / relaunch via Wine.
    public static func hostPathToWindows(_ host: URL, prefix: URL) -> String {
        let driveC = prefix.appendingPathComponent("drive_c").path
        let path = host.path
        if path.hasPrefix(driveC) {
            let rest = path.dropFirst(driveC.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let win = rest.replacingOccurrences(of: "/", with: "\\")
            return "C:\\\(win)"
        }
        return host.lastPathComponent
    }

    /// Maps a host `.exe`/`.msi` under `drive_c` into a Windows path; otherwise returns the host path.
    public static func windowsPathForLaunch(hostPath: String, prefix: URL) -> String {
        hostPathToWindows(URL(fileURLWithPath: hostPath), prefix: prefix)
    }
}
