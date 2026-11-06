import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One kernel anti-cheat title from the bundled AreWeAntiCheatYet extract.
public struct AntiCheatEntry: Codable, Sendable, Equatable, Identifiable {
    public var steamId: String?
    public var epicId: String?
    public var name: String
    public var anticheats: [String]
    public var linuxStatus: String
    public var slug: String

    public var id: String { slug.isEmpty ? (steamId ?? epicId ?? name) : slug }

    public var usesEasyAntiCheat: Bool {
        anticheats.contains { $0.localizedCaseInsensitiveContains("Easy Anti-Cheat") }
    }

    public var usesBattlEye: Bool {
        anticheats.contains { $0.localizedCaseInsensitiveContains("BattlEye") }
    }

    public var shortAnticheatLabel: String {
        anticheats.joined(separator: " + ")
    }

    /// Proton/Linux status is not macOS Wine. Kernel AC still likely fails here.
    public var libraryWarning: String {
        "\(shortAnticheatLabel) — likely won't run"
    }
}

public struct AntiCheatCatalogFile: Codable, Sendable, Equatable {
    public var source: String
    public var sourceUrl: String
    public var homepage: String?
    public var generated: String?
    public var note: String?
    public var games: [AntiCheatEntry]
}

/// Bundled extract of AreWeAntiCheatYet `games.json` (EAC / BattlEye only).
/// Source: https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet
public enum AntiCheatCatalog {
    public static let resourceName = "kernel-anticheat.json"
    public static let remoteURL = URL(
        string: "https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/master/games.json"
    )!

    public static let bundledSourceURL = URL(
        string: "https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet"
    )!

    private static let decoder = JSONDecoder()

    public static func loadBundled(
        from bundles: [Bundle] = VermutResources.coreBundles,
        fileManager: FileManager = .default
    ) -> AntiCheatCatalogFile {
        if let url = locateResource(in: bundles, fileManager: fileManager),
           let data = try? Data(contentsOf: url),
           let file = try? decoder.decode(AntiCheatCatalogFile.self, from: data) {
            return file
        }
        return AntiCheatCatalogFile(
            source: "AreWeAntiCheatYet/AreWeAntiCheatYet",
            sourceUrl: bundledSourceURL.absoluteString,
            homepage: "https://areweanticheatyet.com/",
            generated: nil,
            note: "Bundled catalog missing; using empty set.",
            games: []
        )
    }

    public static func locateResource(
        in bundles: [Bundle],
        fileManager: FileManager = .default
    ) -> URL? {
        for bundle in bundles {
            if let url = bundle.url(forResource: "kernel-anticheat", withExtension: "json") {
                return url
            }
            let beside = bundle.bundleURL.appendingPathComponent(resourceName)
            if fileManager.fileExists(atPath: beside.path) { return beside }
        }
        return nil
    }

    public static func lookup(
        store: GameStore,
        appId: String,
        name: String,
        catalog: AntiCheatCatalogFile = loadBundled()
    ) -> AntiCheatEntry? {
        let trimmedId = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        if store == .steam, !trimmedId.isEmpty {
            if let match = catalog.games.first(where: { $0.steamId == trimmedId }) {
                return match
            }
        }
        if store == .epic, !trimmedId.isEmpty {
            if let match = catalog.games.first(where: { $0.epicId == trimmedId }) {
                return match
            }
        }
        let needle = normalizeName(name)
        guard !needle.isEmpty else { return nil }
        return catalog.games.first { normalizeName($0.name) == needle }
    }

    public static func normalizeName(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return folded.filter { $0.isLetter || $0.isNumber }
    }
}
