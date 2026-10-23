import Foundation

/// One bottle row in the uninstall sheet (store bottle or custom).
public enum UninstallBottleID: Hashable, Sendable, Codable {
    case store(String) // GameStore.identifier
    case custom(UUID)

    public var store: GameStore? {
        if case .store(let id) = self {
            return GameStore.allCases.first { $0.identifier == id }
        }
        return nil
    }
}

/// Top-level removable categories (bottles are expanded separately).
public enum UninstallCategory: String, Hashable, Sendable, CaseIterable, Codable {
    case app
    case bottles
    case engines
    case caches
    case logs
    case preferences
}

/// A concrete trash target prepared for execution.
public struct UninstallTarget: Hashable, Sendable {
    public var id: String
    public var category: UninstallCategory
    public var bottleID: UninstallBottleID?
    public var displayName: String
    public var detail: String
    public var urls: [URL]
    public var byteCount: Int64
    public var isSelected: Bool
    /// When true, the app bundle is trashed by a detached helper after quit.
    public var requiresDetachedAppRemoval: Bool

    public init(
        id: String,
        category: UninstallCategory,
        bottleID: UninstallBottleID? = nil,
        displayName: String,
        detail: String = "",
        urls: [URL],
        byteCount: Int64 = 0,
        isSelected: Bool,
        requiresDetachedAppRemoval: Bool = false
    ) {
        self.id = id
        self.category = category
        self.bottleID = bottleID
        self.displayName = displayName
        self.detail = detail
        self.urls = urls
        self.byteCount = byteCount
        self.isSelected = isSelected
        self.requiresDetachedAppRemoval = requiresDetachedAppRemoval
    }
}

/// Selection + size model for the uninstall sheet.
public struct UninstallPlan: Sendable {
    public var app: UninstallTarget
    public var bottles: [UninstallTarget]
    public var engines: UninstallTarget
    public var caches: UninstallTarget
    public var logs: UninstallTarget
    public var preferences: UninstallTarget
    public var bottlesExpanded: Bool

    public init(
        app: UninstallTarget,
        bottles: [UninstallTarget],
        engines: UninstallTarget,
        caches: UninstallTarget,
        logs: UninstallTarget,
        preferences: UninstallTarget,
        bottlesExpanded: Bool = false
    ) {
        self.app = app
        self.bottles = bottles
        self.engines = engines
        self.caches = caches
        self.logs = logs
        self.preferences = preferences
        self.bottlesExpanded = bottlesExpanded
    }

    public var allTargets: [UninstallTarget] {
        [app] + bottles + [engines, caches, logs, preferences]
    }

    public var selectedTargets: [UninstallTarget] {
        allTargets.filter(\.isSelected)
    }

    public var selectedByteCount: Int64 {
        selectedTargets.reduce(0) { $0 + $1.byteCount }
    }

    public var selectedBottleCount: Int {
        bottles.filter(\.isSelected).count
    }

    public var hasSelectedBottle: Bool {
        selectedBottleCount > 0
    }

    public var keptBottles: [UninstallTarget] {
        bottles.filter { !$0.isSelected }
    }

    public var keptBottlesByteCount: Int64 {
        keptBottles.reduce(0) { $0 + $1.byteCount }
    }

    /// Mixed / on / off for the Bottles parent checkbox.
    public enum TriState: Sendable, Equatable {
        case off
        case on
        case mixed
    }

    public var bottlesTriState: TriState {
        guard !bottles.isEmpty else { return .off }
        let selected = bottles.filter(\.isSelected).count
        if selected == 0 { return .off }
        if selected == bottles.count { return .on }
        return .mixed
    }

    public var isEverythingSelected: Bool {
        allTargets.allSatisfy(\.isSelected)
    }

    public var isNothingSelected: Bool {
        selectedTargets.isEmpty
    }

    public mutating func selectAll() {
        app.isSelected = true
        engines.isSelected = true
        caches.isSelected = true
        logs.isSelected = true
        preferences.isSelected = true
        for i in bottles.indices { bottles[i].isSelected = true }
    }

    public mutating func deselectAll() {
        app.isSelected = false
        engines.isSelected = false
        caches.isSelected = false
        logs.isSelected = false
        preferences.isSelected = false
        for i in bottles.indices { bottles[i].isSelected = false }
    }

    public mutating func setAllBottlesSelected(_ selected: Bool) {
        for i in bottles.indices { bottles[i].isSelected = selected }
    }

    public mutating func setBottleSelected(id: UninstallBottleID, selected: Bool) {
        guard let index = bottles.firstIndex(where: { $0.bottleID == id }) else { return }
        bottles[index].isSelected = selected
    }
}

/// Builds the default uninstall plan from PathManager / bottles on disk.
public enum UninstallPlanBuilder {
    public struct Context: Sendable {
        public var appSupportURL: URL
        public var bottlesURL: URL
        public var enginesURL: URL
        public var cacheURL: URL
        public var configURL: URL
        public var appBundleURL: URL?
        public var customBottles: [CustomBottle]
        public var gameCountByStore: [GameStore: Int]
        public var home: URL
        public var fileManager: FileManager

        public init(
            appSupportURL: URL = PathManager.shared.appSupportURL,
            bottlesURL: URL = PathManager.shared.bottlesURL,
            enginesURL: URL = PathManager.shared.enginesURL,
            cacheURL: URL = PathManager.shared.cacheURL,
            configURL: URL = PathManager.shared.configURL,
            appBundleURL: URL? = Bundle.main.bundleURL,
            customBottles: [CustomBottle] = (try? CustomBottleStore.shared.load()) ?? [],
            gameCountByStore: [GameStore: Int] = [:],
            home: URL = FileManager.default.homeDirectoryForCurrentUser,
            fileManager: FileManager = .default
        ) {
            self.appSupportURL = appSupportURL
            self.bottlesURL = bottlesURL
            self.enginesURL = enginesURL
            self.cacheURL = cacheURL
            self.configURL = configURL
            self.appBundleURL = appBundleURL
            self.customBottles = customBottles
            self.gameCountByStore = gameCountByStore
            self.home = home
            self.fileManager = fileManager
        }
    }

    /// Default: everything selected except bottles.
    public static func makeDefaultPlan(context: Context = Context()) -> UninstallPlan {
        let bottles = makeBottleTargets(context: context, selected: false)
        return UninstallPlan(
            app: makeAppTarget(context: context, selected: true),
            bottles: bottles,
            engines: makeEnginesTarget(context: context, selected: true),
            caches: makeCachesTarget(context: context, selected: true),
            logs: makeLogsTarget(context: context, bottles: bottles, selected: true),
            preferences: makePreferencesTarget(context: context, selected: true),
            bottlesExpanded: false
        )
    }

    public static func makeAppTarget(context: Context, selected: Bool) -> UninstallTarget {
        let url = context.appBundleURL ?? URL(fileURLWithPath: "/Applications/Vermut.app")
        let bytes = UninstallSizeCalculator.byteCount(of: url, fileManager: context.fileManager)
        return UninstallTarget(
            id: "app",
            category: .app,
            displayName: "Vermut app",
            detail: url.path,
            urls: [url],
            byteCount: bytes,
            isSelected: selected,
            requiresDetachedAppRemoval: true
        )
    }

    public static func makeBottleTargets(context: Context, selected: Bool) -> [UninstallTarget] {
        var result: [UninstallTarget] = []
        for store in GameStore.allCases {
            let url = context.bottlesURL.appendingPathComponent(store.identifier, isDirectory: true)
            guard context.fileManager.fileExists(atPath: url.path) else { continue }
            let count = context.gameCountByStore[store] ?? 0
            let detail: String
            if count == 1 {
                detail = "1 game installed"
            } else if count > 1 {
                detail = "\(count) games installed"
            } else {
                detail = store.rawValue
            }
            // Epic Legendary config lives under the epic bottle folder already.
            let bytes = UninstallSizeCalculator.byteCount(of: url, fileManager: context.fileManager)
            result.append(
                UninstallTarget(
                    id: "bottle-\(store.identifier)",
                    category: .bottles,
                    bottleID: .store(store.identifier),
                    displayName: store == .epic ? "Epic Games" : store.rawValue,
                    detail: detail,
                    urls: [url],
                    byteCount: bytes,
                    isSelected: selected
                )
            )
        }
        for bottle in context.customBottles {
            let url = context.bottlesURL.appendingPathComponent(bottle.id.uuidString, isDirectory: true)
            guard context.fileManager.fileExists(atPath: url.path) else { continue }
            let bytes = UninstallSizeCalculator.byteCount(of: url, fileManager: context.fileManager)
            result.append(
                UninstallTarget(
                    id: "bottle-\(bottle.id.uuidString)",
                    category: .bottles,
                    bottleID: .custom(bottle.id),
                    displayName: bottle.name,
                    detail: "Custom bottle",
                    urls: [url],
                    byteCount: bytes,
                    isSelected: selected
                )
            )
        }
        // Index file only when at least one custom bottle exists (or file present).
        let index = context.appSupportURL.appendingPathComponent(CustomBottleStore.indexFileName)
        if context.fileManager.fileExists(atPath: index.path),
           result.contains(where: { if case .custom = $0.bottleID { return true }; return false }) {
            // Index is removed with the last selected custom bottle in the executor.
            _ = index
        }
        return result
    }

    public static func makeEnginesTarget(context: Context, selected: Bool) -> UninstallTarget {
        var urls: [URL] = []
        var names: [String] = []
        for engine in WineEngine.allCases {
            let url = context.enginesURL.appendingPathComponent(engine.id, isDirectory: true)
            if context.fileManager.fileExists(atPath: url.path) {
                urls.append(url)
                names.append(engine.userFacingName)
            }
        }
        for name in ["dxmt", "dxvk", "legendary"] {
            let url = context.enginesURL.appendingPathComponent(name, isDirectory: true)
            if context.fileManager.fileExists(atPath: url.path) {
                urls.append(url)
                names.append(name == "dxmt" ? "DXMT" : name == "dxvk" ? "DXVK" : "Legendary")
            }
        }
        let d3d = D3DMetalDetector.vermutLibraryURL(appSupport: context.appSupportURL)
        if context.fileManager.fileExists(atPath: d3d.path) {
            urls.append(d3d)
            names.append("D3DMetal copy")
        }
        let bytes = urls.reduce(Int64(0)) {
            $0 + UninstallSizeCalculator.byteCount(of: $1, fileManager: context.fileManager)
        }
        return UninstallTarget(
            id: "engines",
            category: .engines,
            displayName: "Engines",
            detail: names.isEmpty ? "Wine engines and graphics layers" : names.joined(separator: ", "),
            urls: urls,
            byteCount: bytes,
            isSelected: selected
        )
    }

    public static func makeCachesTarget(context: Context, selected: Bool) -> UninstallTarget {
        var urls: [URL] = []
        var parts: [String] = []
        if context.fileManager.fileExists(atPath: context.cacheURL.path) {
            urls.append(context.cacheURL)
            parts.append("Covers, store installers")
        }
        let legacy = UninstallPathPolicy.legacyCaskLauncherURL(home: context.home)
        // Only list legacy when it is a distinct leftover (not the active appSupport).
        if context.fileManager.fileExists(atPath: legacy.path),
           legacy.standardizedFileURL != context.appSupportURL.standardizedFileURL {
            urls.append(legacy)
            parts.append("Old data folder (CaskLauncher)")
        }
        let bytes = urls.reduce(Int64(0)) {
            $0 + UninstallSizeCalculator.byteCount(of: $1, fileManager: context.fileManager)
        }
        return UninstallTarget(
            id: "caches",
            category: .caches,
            displayName: "Caches",
            detail: parts.joined(separator: " · "),
            urls: urls,
            byteCount: bytes,
            isSelected: selected
        )
    }

    public static func makeLogsTarget(
        context: Context,
        bottles: [UninstallTarget],
        selected: Bool
    ) -> UninstallTarget {
        // Logs for bottles that are *not* selected for removal, plus ~/Library/Logs/Vermut.
        var urls: [URL] = []
        let selectedBottlePaths = Set(
            bottles.filter(\.isSelected).flatMap(\.urls).map { $0.standardizedFileURL.path }
        )
        for store in GameStore.allCases {
            let bottle = context.bottlesURL.appendingPathComponent(store.identifier, isDirectory: true)
            if selectedBottlePaths.contains(bottle.standardizedFileURL.path) { continue }
            let logs = bottle.appendingPathComponent("logs", isDirectory: true)
            if context.fileManager.fileExists(atPath: logs.path) {
                urls.append(logs)
            }
        }
        for bottle in context.customBottles {
            let root = context.bottlesURL.appendingPathComponent(bottle.id.uuidString, isDirectory: true)
            if selectedBottlePaths.contains(root.standardizedFileURL.path) { continue }
            let logs = root.appendingPathComponent("logs", isDirectory: true)
            if context.fileManager.fileExists(atPath: logs.path) {
                urls.append(logs)
            }
        }
        let systemLogs = UninstallPathPolicy.systemLogsURL(home: context.home)
        if context.fileManager.fileExists(atPath: systemLogs.path) {
            urls.append(systemLogs)
        }
        let bytes = urls.reduce(Int64(0)) {
            $0 + UninstallSizeCalculator.byteCount(of: $1, fileManager: context.fileManager)
        }
        return UninstallTarget(
            id: "logs",
            category: .logs,
            displayName: "Logs",
            detail: urls.isEmpty ? "" : "Bottle and app logs",
            urls: urls,
            byteCount: bytes,
            isSelected: selected
        )
    }

    public static func makePreferencesTarget(context: Context, selected: Bool) -> UninstallTarget {
        var urls: [URL] = []
        if context.fileManager.fileExists(atPath: context.configURL.path) {
            urls.append(context.configURL)
        }
        urls.append(contentsOf: UninstallPathPolicy.preferenceRelatedURLs(
            home: context.home,
            fileManager: context.fileManager
        ).filter { context.fileManager.fileExists(atPath: $0.path) })
        let bytes = urls.reduce(Int64(0)) {
            $0 + UninstallSizeCalculator.byteCount(of: $1, fileManager: context.fileManager)
        }
        return UninstallTarget(
            id: "preferences",
            category: .preferences,
            displayName: "Preferences",
            detail: UninstallPathPolicy.bundleIdentifier,
            urls: urls,
            byteCount: bytes,
            isSelected: selected
        )
    }

    /// Recomputes log URLs when bottle selection changes (logs of removed bottles go with the bottle).
    public static func refreshLogs(plan: inout UninstallPlan, context: Context) {
        let selected = plan.logs.isSelected
        plan.logs = makeLogsTarget(context: context, bottles: plan.bottles, selected: selected)
    }
}

/// Directory size that never follows Wine `dosdevices/z:` or other symlinks.
public enum UninstallSizeCalculator {
    public static func byteCount(of url: URL, fileManager: FileManager = .default) -> Int64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { return 0 }
            return Int64(values?.fileSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            if UninstallPathPolicy.isWineZDriveSymlink(fileURL) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey
            ])
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values?.isDirectory == true { continue }
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    public static func formattedByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }
}
