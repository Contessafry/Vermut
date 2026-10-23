import Foundation

/// Loads and saves per-game JSON under `bottles/<store>/games/<appId>.json`.
public enum GameSettingsStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    public static func load(
        store: GameStore,
        appId: String,
        pathManager: PathManager = .shared,
        fileManager: FileManager = .default
    ) -> GameConfiguration {
        let url = pathManager.gameConfigURL(for: store, appId: appId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let config = try? decoder.decode(GameConfiguration.self, from: data)
        else {
            return .automatic
        }
        return config
    }

    public static func save(
        _ config: GameConfiguration,
        store: GameStore,
        appId: String,
        pathManager: PathManager = .shared,
        fileManager: FileManager = .default
    ) throws {
        let url = pathManager.gameConfigURL(for: store, appId: appId)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !config.hasOverrides {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return
        }
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    public static func reset(
        store: GameStore,
        appId: String,
        pathManager: PathManager = .shared,
        fileManager: FileManager = .default
    ) throws {
        try save(.automatic, store: store, appId: appId, pathManager: pathManager, fileManager: fileManager)
    }
}
