import Foundation

public final class SteamHelper: @unchecked Sendable {
    public static let shared = SteamHelper()

    private let fileManager = FileManager.default

    private init() {}

    /// Restores steamwebhelper.exe if an older CaskLauncher build replaced it with a shell wrapper.
    public func restoreOriginalSteamWebHelper(in prefixURL: URL) throws {
        let steamPath = prefixURL.appendingPathComponent("drive_c/Program Files (x86)/Steam")
        let webhelper = steamPath.appendingPathComponent("steamwebhelper.exe")
        let backup = steamPath.appendingPathComponent("steamwebhelper.exe.original")
        let wrapper = steamPath.appendingPathComponent("steamwebhelper_wrapper.sh")

        if fileManager.fileExists(atPath: backup.path) {
            if fileManager.fileExists(atPath: webhelper.path) {
                try fileManager.removeItem(at: webhelper)
            }
            try fileManager.moveItem(at: backup, to: webhelper)
        }

        if fileManager.fileExists(atPath: wrapper.path) {
            try fileManager.removeItem(at: wrapper)
        }
    }

    public func isWrappedSteamWebHelper(in prefixURL: URL) -> Bool {
        let webhelper = prefixURL.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamwebhelper.exe"
        )
        guard let handle = try? FileHandle(forReadingFrom: webhelper) else {
            return false
        }
        defer { try? handle.close() }
        let prefix = try? handle.read(upToCount: 2)
        return prefix == Data("#!".utf8)
    }

    public func listInstalledGames(in prefixURL: URL) throws -> [SteamGame] {
        StoreLibrary.shared.steamGames(in: prefixURL).map {
            SteamGame(appId: $0.appId, name: $0.name, installDir: $0.installDir)
        }
    }
}

public struct SteamGame: Identifiable, Sendable {
    public let appId: String
    public let name: String
    public let installDir: String?

    public var id: String { appId }
}
