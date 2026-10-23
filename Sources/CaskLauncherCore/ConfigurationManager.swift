import Foundation

public final class ConfigurationManager: @unchecked Sendable {
    public static let shared = ConfigurationManager()
    
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let fileManager = FileManager.default
    
    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    
    public func loadConfiguration() throws -> AppConfiguration {
        let configURL = PathManager.shared.configURL
        
        guard fileManager.fileExists(atPath: configURL.path) else {
            let defaultConfig = AppConfiguration()
            // Never recreate config.json during / after an uninstall wipe.
            if !UninstallPersistenceGate.writesSuppressed {
                try saveConfiguration(defaultConfig)
            }
            return defaultConfig
        }
        
        let data = try Data(contentsOf: configURL)
        var config = try decoder.decode(AppConfiguration.self, from: data)
        if config.migrateLegacyEngineIfNeeded() {
            try saveConfiguration(config)
        }
        return config
    }
    
    public func saveConfiguration(_ config: AppConfiguration) throws {
        if UninstallPersistenceGate.writesSuppressed { return }
        let configURL = PathManager.shared.configURL
        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }
}
