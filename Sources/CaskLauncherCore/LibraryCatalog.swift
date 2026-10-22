import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A game installed in a store bottle, parsed from that store’s own files.
public struct InstalledGame: Identifiable, Sendable, Equatable {
    public let store: GameStore
    public let appId: String
    public let name: String
    public let installDir: String?
    public let coverURLs: [URL]
    public let isInstalled: Bool

    public var id: String { "\(store.identifier)-\(appId)" }

    public init(
        store: GameStore,
        appId: String,
        name: String,
        installDir: String? = nil,
        coverURLs: [URL] = [],
        isInstalled: Bool = true
    ) {
        self.store = store
        self.appId = appId
        self.name = name
        self.installDir = installDir
        self.coverURLs = coverURLs
        self.isInstalled = isInstalled
    }
}

/// In-progress Legendary (or other) game download shown in Downloads.
public struct GameDownload: Identifiable, Sendable, Equatable {
    public let store: GameStore
    public let appId: String
    public let name: String
    public var progress: Double
    public var detail: String
    public var error: String?

    public var id: String { "\(store.identifier)-\(appId)" }

    public init(
        store: GameStore,
        appId: String,
        name: String,
        progress: Double = 0,
        detail: String = "",
        error: String? = nil
    ) {
        self.store = store
        self.appId = appId
        self.name = name
        self.progress = progress
        self.detail = detail
        self.error = error
    }

    public var isFailed: Bool { error != nil }
}

/// Valve Data Format / KeyValues tokenizer used for `appmanifest_*.acf`
/// and `libraryfolders.vdf`.
///
/// ACF lines are `"key"\t\t"value"`. Splitting on quotes treats the tab padding
/// as the value (`"\t\t"`), and regex `\s` is not reliable across Foundation
/// implementations. Whitespace is skipped between tokens instead.
public enum ValveKeyValues {
    public enum Token: Equatable, Sendable {
        case string(String)
        case objectStart
        case objectEnd
    }

    public static func tokenize(_ content: String) -> [Token] {
        let chars = Array(content)
        var tokens: [Token] = []
        var i = 0

        func skipWhitespaceAndComments() {
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace {
                    i += 1
                    continue
                }
                if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    i += 2
                    while i < chars.count, chars[i] != "\n" {
                        i += 1
                    }
                    continue
                }
                if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") {
                        i += 1
                    }
                    if i + 1 < chars.count {
                        i += 2
                    } else {
                        i = chars.count
                    }
                    continue
                }
                break
            }
        }

        while i < chars.count {
            skipWhitespaceAndComments()
            guard i < chars.count else { break }
            let c = chars[i]
            if c == "{" {
                tokens.append(.objectStart)
                i += 1
                continue
            }
            if c == "}" {
                tokens.append(.objectEnd)
                i += 1
                continue
            }
            if c == "\"" {
                i += 1
                var value = ""
                while i < chars.count {
                    let ch = chars[i]
                    if ch == "\\" {
                        i += 1
                        guard i < chars.count else { break }
                        switch chars[i] {
                        case "n": value.append("\n")
                        case "t": value.append("\t")
                        case "r": value.append("\r")
                        case "\"": value.append("\"")
                        case "\\": value.append("\\")
                        default: value.append(chars[i])
                        }
                        i += 1
                        continue
                    }
                    if ch == "\"" {
                        i += 1
                        break
                    }
                    value.append(ch)
                    i += 1
                }
                tokens.append(.string(value))
                continue
            }

            var value = ""
            while i < chars.count {
                let ch = chars[i]
                if ch.isWhitespace || ch == "{" || ch == "}" {
                    break
                }
                value.append(ch)
                i += 1
            }
            if !value.isEmpty {
                tokens.append(.string(value))
            }
        }
        return tokens
    }

    /// First occurrence of each string key/value pair. Nested tables reuse names
    /// (`UserConfig.name`); taking the first match matches AppState’s `name` / `appid`.
    public static func firstStringValues(in content: String) -> [String: String] {
        var result: [String: String] = [:]
        let tokens = tokenize(content)
        var index = 0
        while index < tokens.count {
            guard case .string(let key) = tokens[index] else {
                index += 1
                continue
            }
            let next = index + 1
            if next < tokens.count, case .string(let value) = tokens[next] {
                if result[key] == nil {
                    result[key] = value
                }
                index += 2
                continue
            }
            index += 1
        }
        return result
    }

    /// Every string value for `key`, including nested tables (`libraryfolders.vdf` `path`).
    public static func allStringValues(forKey key: String, in content: String) -> [String] {
        var values: [String] = []
        let tokens = tokenize(content)
        var index = 0
        while index < tokens.count {
            if case .string(let found) = tokens[index], found == key {
                let next = index + 1
                if next < tokens.count, case .string(let value) = tokens[next] {
                    values.append(value)
                    index += 2
                    continue
                }
            }
            index += 1
        }
        return values
    }
}

public enum SteamArtwork {
    public static func coverURLs(appId: String) -> [URL] {
        let id = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            URL(string: "https://steamcdn-a.akamaihd.net/steam/apps/\(id)/library_600x900.jpg"),
            URL(string: "https://steamcdn-a.akamaihd.net/steam/apps/\(id)/header.jpg")
        ].compactMap { $0 }
    }
}

public final class StoreLibrary: @unchecked Sendable {
    public static let shared = StoreLibrary()

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func listAll(epicOverlay: [InstalledGame]? = nil) -> [InstalledGame] {
        var games: [InstalledGame] = []
        games.append(contentsOf: steamGames(in: PathManager.shared.prefixURL(for: .steam)))
        games.append(contentsOf: gogGames(in: PathManager.shared.prefixURL(for: .gog)))
        if let epicOverlay, !epicOverlay.isEmpty {
            games.append(contentsOf: epicOverlay)
        } else {
            games.append(contentsOf: epicGames(in: PathManager.shared.prefixURL(for: .epic)))
        }
        return games.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func steamGames(in prefixURL: URL) -> [InstalledGame] {
        let roots = steamRoots(in: prefixURL)
        return steamappsDirectories(in: prefixURL).flatMap { steamapps in
            (try? parseSteamapps(steamapps)) ?? []
        }.map { game in
            InstalledGame(
                store: game.store,
                appId: game.appId,
                name: game.name,
                installDir: game.installDir,
                coverURLs: steamCoverURLs(for: game, roots: roots),
                isInstalled: game.isInstalled
            )
        }
    }

    public func epicGames(in prefixURL: URL) -> [InstalledGame] {
        epicManifestDirectories(in: prefixURL).flatMap { dir in
            (try? parseEpicManifests(dir)) ?? []
        }
    }

    public func gogGames(in prefixURL: URL) -> [InstalledGame] {
        (try? parseGOGInfos(in: prefixURL)) ?? []
    }

    // MARK: Steam

    private static let skippedSteamAppIDs: Set<String> = [
        "228980", "1070560", "1391110", "1628350", "2180100", "1493710", "1887720"
    ]

    private func steamRoots(in prefixURL: URL) -> [URL] {
        [
            prefixURL.appendingPathComponent("drive_c/Program Files (x86)/Steam"),
            prefixURL.appendingPathComponent("drive_c/Program Files/Steam")
        ].filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func steamappsDirectories(in prefixURL: URL) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        let defaults = steamRoots(in: prefixURL).map { $0.appendingPathComponent("steamapps") }
        for url in defaults where fileManager.fileExists(atPath: url.path) {
            if seen.insert(url.path).inserted { result.append(url) }
        }
        for steamapps in result {
            let vdf = steamapps.appendingPathComponent("libraryfolders.vdf")
            guard let content = try? String(contentsOf: vdf, encoding: .utf8) else { continue }
            // libraryfolders.vdf repeats "path"; scan every occurrence.
            for windows in ValveKeyValues.allStringValues(forKey: "path", in: content) {
                if let unix = windowsSteamPath(windows, prefix: prefixURL) {
                    let extra = unix.appendingPathComponent("steamapps")
                    if fileManager.fileExists(atPath: extra.path), seen.insert(extra.path).inserted {
                        result.append(extra)
                    }
                }
            }
        }
        return result
    }

    private func windowsSteamPath(_ windows: String, prefix: URL) -> URL? {
        var path = windows.replacingOccurrences(of: "\\\\", with: "/")
            .replacingOccurrences(of: "\\", with: "/")
        if let colon = path.firstIndex(of: ":") {
            let drive = String(path[path.startIndex]).lowercased()
            path = String(path[path.index(after: colon)...])
            if path.hasPrefix("/") { path.removeFirst() }
            return prefix.appendingPathComponent("drive_\(drive)").appendingPathComponent(path)
        }
        return nil
    }

    private func parseSteamapps(_ steamapps: URL) throws -> [InstalledGame] {
        let contents = try fileManager.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)
        let acfFiles = contents.filter {
            $0.pathExtension == "acf" && $0.lastPathComponent.hasPrefix("appmanifest_")
        }
        return acfFiles.compactMap { parseSteamACF($0) }
    }

    private func steamCoverURLs(for game: InstalledGame, roots: [URL]) -> [URL] {
        guard !game.appId.isEmpty, game.appId.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return game.coverURLs
        }
        let caches = roots.map {
            $0.appendingPathComponent("appcache/librarycache/\(game.appId)", isDirectory: true)
        }
        let portraits = localSteamArt(in: caches, named: ["library_600x900.jpg", "library_capsule.jpg"])
        let headers = localSteamArt(in: caches, named: ["header.jpg", "library_header.jpg"])
        return portraits + game.coverURLs + headers
    }

    private func localSteamArt(in caches: [URL], named names: [String]) -> [URL] {
        caches.flatMap { cache -> [URL] in
            let hashed = ((try? fileManager.contentsOfDirectory(
                at: cache,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            return names.flatMap { name in
                ([cache] + hashed).map { $0.appendingPathComponent(name) }
            }
        }.filter { fileManager.fileExists(atPath: $0.path) }
    }

    public func parseSteamACF(_ url: URL) -> InstalledGame? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parseSteamACF(content: content)
    }

    public func parseSteamACF(content: String) -> InstalledGame? {
        let values = ValveKeyValues.firstStringValues(in: content)
        guard let appId = values["appid"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !appId.isEmpty,
              let name = values["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }

        if Self.skippedSteamAppIDs.contains(appId) { return nil }
        let lowered = name.lowercased()
        if lowered.contains("steamworks common") { return nil }
        if lowered.hasPrefix("steam linux runtime") { return nil }

        if let flags = values["StateFlags"], let flagValue = Int(flags) {
            // Bit 2 (value 4) = fully installed.
            if flagValue & 4 == 0 { return nil }
        }

        return InstalledGame(
            store: .steam,
            appId: appId,
            name: name,
            installDir: values["installdir"],
            coverURLs: SteamArtwork.coverURLs(appId: appId)
        )
    }

    // MARK: Epic

    private func epicManifestDirectories(in prefixURL: URL) -> [URL] {
        [
            prefixURL.appendingPathComponent("drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests"),
            prefixURL.appendingPathComponent("drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Data/Manifests"),
            prefixURL.appendingPathComponent("drive_c/Program Files/Epic Games/EpicGamesLauncher/Data/Manifests")
        ].filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func parseEpicManifests(_ directory: URL) throws -> [InstalledGame] {
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "item" }
        return files.compactMap { parseEpicItem($0) }
    }

    public func parseEpicItem(_ url: URL) -> InstalledGame? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseEpicItem(data: data)
    }

    public func parseEpicItem(data: Data) -> InstalledGame? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if json["bIsIncompleteInstall"] as? Bool == true { return nil }
        let name = (json["DisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let appName = (json["AppName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, !appName.isEmpty else { return nil }
        let install = json["InstallLocation"] as? String
        return InstalledGame(
            store: .epic,
            appId: appName,
            name: name,
            installDir: install,
            coverURLs: []
        )
    }

    // MARK: GOG

    public func parseGOGInfos(in prefixURL: URL) throws -> [InstalledGame] {
        let roots = [
            prefixURL.appendingPathComponent("drive_c/Program Files (x86)/GOG Galaxy/Games"),
            prefixURL.appendingPathComponent("drive_c/Program Files/GOG Galaxy/Games"),
            prefixURL.appendingPathComponent("drive_c/GOG Games")
        ].filter { fileManager.fileExists(atPath: $0.path) }

        var games: [InstalledGame] = []
        var seen = Set<String>()
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                let name = fileURL.lastPathComponent
                guard name.hasPrefix("goggame-"), name.hasSuffix(".info") else { continue }
                if let game = parseGOGInfo(fileURL), seen.insert(game.id).inserted {
                    games.append(game)
                }
            }
        }
        return games
    }

    public func parseGOGInfo(_ url: URL) -> InstalledGame? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseGOGInfo(data: data, fileURL: url)
    }

    public func parseGOGInfo(data: Data, fileURL: URL? = nil) -> InstalledGame? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let gameId = (json["gameId"] as? String)
            ?? (json["rootGameId"] as? String)
            ?? ""
        guard !name.isEmpty, !gameId.isEmpty else { return nil }

        var covers: [URL] = []
        if let folder = fileURL?.deletingLastPathComponent() {
            covers.append(contentsOf: localGOGCovers(in: folder))
        }

        return InstalledGame(
            store: .gog,
            appId: gameId,
            name: name,
            installDir: fileURL?.deletingLastPathComponent().path,
            coverURLs: covers
        )
    }

    private func localGOGCovers(in folder: URL) -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let preferred = names.filter { url in
            let lower = url.lastPathComponent.lowercased()
            return lower.contains("vertical") && (lower.hasSuffix(".jpg") || lower.hasSuffix(".png") || lower.hasSuffix(".webp"))
                || lower.contains("cover") && (lower.hasSuffix(".jpg") || lower.hasSuffix(".png") || lower.hasSuffix(".webp"))
        }
        return preferred.sorted { $0.lastPathComponent.count < $1.lastPathComponent.count }
    }
}

/// Disk cache for store CDN / local cover art.
public enum CoverCache {
    public static func fileURL(store: GameStore, appId: String) -> URL {
        PathManager.shared.cacheURL
            .appendingPathComponent("covers", isDirectory: true)
            .appendingPathComponent("\(store.identifier)-\(appId).img")
    }

    public static func load(urls: [URL], store: GameStore, appId: String) async -> Data? {
        let dest = fileURL(store: store, appId: appId)
        if let cached = try? Data(contentsOf: dest), isImageData(cached) {
            return cached
        }
        for url in urls {
            guard let data = await fetch(url), isImageData(data) else { continue }
            try? FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: dest, options: .atomic)
            return data
        }
        return nil
    }

    public static func isImageData(_ data: Data) -> Bool {
        guard data.count > 24 else { return false }
        let bytes = [UInt8](data.prefix(12))
        if bytes[0] == 0xFF && bytes[1] == 0xD8 { return true } // JPEG
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 { return true } // PNG
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 { return true } // GIF
        if bytes.count >= 12, bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return true // WebP
        }
        return false
    }

    private static func fetch(_ url: URL) async -> Data? {
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }
        var request = URLRequest(url: url)
        request.setValue("Vermut/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return nil
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        return data
    }
}
