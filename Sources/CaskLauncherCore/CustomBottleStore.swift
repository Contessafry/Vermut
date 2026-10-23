import Foundation

/// Atomic index of custom bottles (`custom-bottles.json` under Application Support).
public final class CustomBottleStore: @unchecked Sendable {
    public static let shared = CustomBottleStore()

    public static let indexFileName = "custom-bottles.json"

    private let fileManager: FileManager
    private let lock = NSLock()
    private var cache: [CustomBottle]?

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func indexURL(appSupport: URL = PathManager.shared.appSupportURL) -> URL {
        appSupport.appendingPathComponent(Self.indexFileName)
    }

    public func load(appSupport: URL = PathManager.shared.appSupportURL) throws -> [CustomBottle] {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        let url = indexURL(appSupport: appSupport)
        guard fileManager.fileExists(atPath: url.path) else {
            cache = []
            return []
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([CustomBottle].self, from: data)
        cache = decoded
        return decoded
    }

    public func save(_ bottles: [CustomBottle], appSupport: URL = PathManager.shared.appSupportURL) throws {
        lock.lock()
        defer { lock.unlock() }
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bottles)
        let url = indexURL(appSupport: appSupport)
        let temp = url.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: temp, to: url)
        cache = bottles
    }

    public func invalidateCache() {
        lock.lock()
        cache = nil
        lock.unlock()
    }

    public func bottle(id: UUID, appSupport: URL = PathManager.shared.appSupportURL) throws -> CustomBottle? {
        try load(appSupport: appSupport).first { $0.id == id }
    }

    public func upsert(_ bottle: CustomBottle, appSupport: URL = PathManager.shared.appSupportURL) throws {
        var bottles = try load(appSupport: appSupport)
        if let index = bottles.firstIndex(where: { $0.id == bottle.id }) {
            bottles[index] = bottle
        } else {
            bottles.append(bottle)
        }
        try save(bottles, appSupport: appSupport)
    }

    public func remove(id: UUID, appSupport: URL = PathManager.shared.appSupportURL) throws {
        var bottles = try load(appSupport: appSupport)
        bottles.removeAll { $0.id == id }
        try save(bottles, appSupport: appSupport)
    }

    public func allNames(appSupport: URL = PathManager.shared.appSupportURL) throws -> [String] {
        try load(appSupport: appSupport).map(\.name)
    }
}
