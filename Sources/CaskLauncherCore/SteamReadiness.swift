import Foundation

/// Decides whether a freshly installed Steam client has finished its first
/// self-update. SteamSetup only lays down a bootstrapper (steam.exe); the real
/// client (SteamUI.dll + CEF steamwebhelper.exe) arrives with the first update.
public enum SteamReadiness {
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
}
