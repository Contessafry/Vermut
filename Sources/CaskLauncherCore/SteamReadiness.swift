import Foundation

/// Decides whether a freshly installed Steam client has finished its first
/// self-update. SteamSetup only lays down a bootstrapper (steam.exe); the real
/// client (SteamUI.dll + CEF steamwebhelper.exe) arrives with the first update.
public enum SteamReadiness {
    public static let firstLaunchAttempts = 4
    public static let firstLaunchRetryDelayNanos: UInt64 = 5_000_000_000
    /// Auto-relaunches when the bootstrapper exits before SteamUI/CEF are on disk.
    public static let bootstrapRelaunchAttempts = 3

    public static func isClientReady(steamDirectory dir: URL, fileManager fm: FileManager = .default) -> Bool {
        guard fm.fileExists(atPath: dir.appendingPathComponent("steam.exe").path),
              fm.fileExists(atPath: dir.appendingPathComponent("SteamUI.dll").path) else { return false }
        let cef = dir.appendingPathComponent("bin/cef")
        let flavors = (try? fm.contentsOfDirectory(atPath: cef.path)) ?? []
        return flavors.contains { flavor in
            fm.fileExists(atPath: cef.appendingPathComponent(flavor).appendingPathComponent("steamwebhelper.exe").path)
        }
    }

    public static func isClientReady(inPrefix prefixURL: URL, fileManager fm: FileManager = .default) -> Bool {
        StoreExecutable.searchRoots(in: prefixURL, store: GameStore.steam).contains { isClientReady(steamDirectory: $0, fileManager: fm) }
    }

    /// Bootstrapper-only install (steam.exe after SteamSetup) is not a usable client.
    public static func isSteamClientInstalled(inPrefix prefixURL: URL, fileManager fm: FileManager = .default) -> Bool {
        isClientReady(inPrefix: prefixURL, fileManager: fm)
    }

    /// Whether first-update should spawn steam.exe again after an early exit.
    public static func shouldRelaunchBootstrap(
        isRunning: Bool,
        clientReady: Bool,
        relaunchesSoFar: Int,
        maxRelaunches: Int = bootstrapRelaunchAttempts
    ) -> Bool {
        !isRunning && !clientReady && relaunchesSoFar < maxRelaunches
    }
}
