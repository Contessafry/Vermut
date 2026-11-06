import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Outcome for a single uninstall data target.
public struct UninstallItemResult: Identifiable, Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable {
        case removed
        case failed
        case skipped
        case kept
    }

    public var id: String { targetID }
    public var targetID: String
    public var displayName: String
    public var byteCount: Int64
    public var outcome: Outcome
    public var message: String?
    public var revealURL: URL?

    public init(
        targetID: String,
        displayName: String,
        byteCount: Int64,
        outcome: Outcome,
        message: String? = nil,
        revealURL: URL? = nil
    ) {
        self.targetID = targetID
        self.displayName = displayName
        self.byteCount = byteCount
        self.outcome = outcome
        self.message = message
        self.revealURL = revealURL
    }
}

public struct UninstallRunSummary: Sendable {
    public var results: [UninstallItemResult]
    public var removedByteCount: Int64
    public var keptBottleCount: Int
    public var keptBottleBytes: Int64
    public var keptBottlesPath: URL?

    public init(
        results: [UninstallItemResult],
        removedByteCount: Int64,
        keptBottleCount: Int,
        keptBottleBytes: Int64,
        keptBottlesPath: URL?
    ) {
        self.results = results
        self.removedByteCount = removedByteCount
        self.keptBottleCount = keptBottleCount
        self.keptBottleBytes = keptBottleBytes
        self.keptBottlesPath = keptBottlesPath
    }

    public var hasFailures: Bool {
        results.contains { $0.outcome == .failed || $0.outcome == .skipped }
    }

    public var failureResults: [UninstallItemResult] {
        results.filter { $0.outcome == .failed || $0.outcome == .skipped }
    }

    public var successResults: [UninstallItemResult] {
        results.filter { $0.outcome == .removed }
    }
}

/// Trashes selected Vermut **data** via `FileManager.trashItem`.
/// Never removes `Vermut.app` (product pivot — user quits and drags the app to Trash).
public enum UninstallExecutor {
    public struct Options: Sendable {
        public var appSupportURL: URL
        public var home: URL
        public var fileManager: FileManager
        public var clearUserDefaults: Bool

        public init(
            appSupportURL: URL = PathManager.shared.appSupportURL,
            home: URL = FileManager.default.homeDirectoryForCurrentUser,
            fileManager: FileManager = .default,
            clearUserDefaults: Bool = true
        ) {
            self.appSupportURL = appSupportURL
            self.home = home
            self.fileManager = fileManager
            self.clearUserDefaults = clearUserDefaults
        }
    }

    public enum ProgressEvent: Sendable {
        case started(displayName: String, index: Int, total: Int)
        case finished(UninstallItemResult)
    }

    /// Removal order: logs → caches → engines → bottles → preferences.
    public static func orderedTargets(from plan: UninstallPlan) -> [UninstallTarget] {
        var ordered: [UninstallTarget] = []
        if plan.logs.isSelected { ordered.append(plan.logs) }
        if plan.caches.isSelected { ordered.append(plan.caches) }
        if plan.engines.isSelected { ordered.append(plan.engines) }
        ordered.append(contentsOf: plan.bottles.filter(\.isSelected))
        if plan.preferences.isSelected { ordered.append(plan.preferences) }
        return ordered
    }

    public static func run(
        plan: UninstallPlan,
        options: Options = Options(),
        progress: ((ProgressEvent) -> Void)? = nil,
        isCancelled: () -> Bool = { false }
    ) -> UninstallRunSummary {
        let allowed = UninstallPathPolicy.allowedPrefixes(
            appSupport: options.appSupportURL,
            appBundle: nil,
            home: options.home
        )
        let targets = orderedTargets(from: plan)
        var results: [UninstallItemResult] = []
        var removedBytes: Int64 = 0
        let total = max(targets.count, 1)

        for (index, target) in targets.enumerated() {
            if isCancelled() { break }
            progress?(.started(displayName: target.displayName, index: index + 1, total: total))

            if target.category == .preferences, options.clearUserDefaults {
                UserDefaults.standard.removePersistentDomain(
                    forName: UninstallPathPolicy.bundleIdentifier
                )
                UserDefaults.standard.synchronize()
            }

            var urls = target.urls
            if target.category == .bottles,
               plan.bottles.allSatisfy(\.isSelected),
               target.id == plan.bottles.first(where: \.isSelected)?.id {
                let indexURL = options.appSupportURL.appendingPathComponent(
                    CustomBottleStore.indexFileName
                )
                if options.fileManager.fileExists(atPath: indexURL.path) {
                    urls.append(indexURL)
                }
            }

            let item = trashURLs(
                urls,
                target: target,
                allowed: allowed,
                home: options.home,
                fileManager: options.fileManager
            )
            results.append(item)
            if item.outcome == .removed { removedBytes += target.byteCount }
            progress?(.finished(item))
        }

        if !isCancelled() {
            finalizeAppSupportCleanup(
                plan: plan,
                appSupport: options.appSupportURL,
                allowed: allowed,
                home: options.home,
                fileManager: options.fileManager
            )
        }

        let kept = plan.keptBottles
        return UninstallRunSummary(
            results: results,
            removedByteCount: removedBytes,
            keptBottleCount: kept.count,
            keptBottleBytes: plan.keptBottlesByteCount,
            keptBottlesPath: kept.isEmpty
                ? nil
                : options.appSupportURL.appendingPathComponent("bottles", isDirectory: true)
        )
    }

    private static func trashURLs(
        _ urls: [URL],
        target: UninstallTarget,
        allowed: [URL],
        home: URL,
        fileManager: FileManager
    ) -> UninstallItemResult {
        var lastError: String?
        var reveal: URL?
        var anyRemoved = false
        var anySkipped = false

        for url in urls {
            if let reason = UninstallPathPolicy.validateForRemoval(
                url,
                allowedPrefixes: allowed,
                home: home
            ) {
                anySkipped = true
                lastError = reason
                reveal = url
                continue
            }
            do {
                try trashURL(url, fileManager: fileManager)
                anyRemoved = true
            } catch {
                let ns = error as NSError
                if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteNoPermissionError
                    || ns.code == NSFileReadNoPermissionError {
                    lastError = "Permission denied. Drag it to the Trash from Finder."
                } else if ns.domain == NSPOSIXErrorDomain, ns.code == EBUSY || ns.code == ETXTBSY {
                    lastError = "File in use."
                } else {
                    lastError = error.localizedDescription
                }
                reveal = url
            }
        }

        if anySkipped, !anyRemoved {
            return UninstallItemResult(
                targetID: target.id,
                displayName: target.displayName,
                byteCount: target.byteCount,
                outcome: .skipped,
                message: lastError ?? "Skipped for safety: path is outside Vermut's folder.",
                revealURL: reveal
            )
        }
        if let lastError, !anyRemoved {
            return UninstallItemResult(
                targetID: target.id,
                displayName: target.displayName,
                byteCount: target.byteCount,
                outcome: .failed,
                message: lastError,
                revealURL: reveal
            )
        }
        if let lastError, anyRemoved {
            return UninstallItemResult(
                targetID: target.id,
                displayName: target.displayName,
                byteCount: target.byteCount,
                outcome: .failed,
                message: lastError,
                revealURL: reveal
            )
        }
        return UninstallItemResult(
            targetID: target.id,
            displayName: target.displayName,
            byteCount: target.byteCount,
            outcome: .removed,
            message: nil,
            revealURL: nil
        )
    }

    /// After selected removals: drop residual whitelist files / empty dirs, then the root if empty.
    public static func finalizeAppSupportCleanup(
        plan: UninstallPlan,
        appSupport: URL,
        allowed: [URL],
        home: URL,
        fileManager: FileManager
    ) {
        let bottlesAllSelected = plan.bottles.isEmpty || plan.bottles.allSatisfy(\.isSelected)
        let fullDataWipe = bottlesAllSelected
            && plan.engines.isSelected
            && plan.caches.isSelected
            && plan.preferences.isSelected

        guard fileManager.fileExists(atPath: appSupport.path) else { return }

        func trashIfSafe(_ url: URL) {
            guard fileManager.fileExists(atPath: url.path) else { return }
            if UninstallPathPolicy.validateForRemoval(
                url,
                allowedPrefixes: allowed,
                home: home
            ) != nil {
                return
            }
            try? trashURL(url, fileManager: fileManager)
        }

        if plan.preferences.isSelected {
            trashIfSafe(appSupport.appendingPathComponent("config.json"))
            if bottlesAllSelected {
                trashIfSafe(appSupport.appendingPathComponent(CustomBottleStore.indexFileName))
            }
        }

        if bottlesAllSelected {
            trashIfSafe(appSupport.appendingPathComponent("bottles", isDirectory: true))
        }

        if plan.engines.isSelected {
            trashIfSafe(appSupport.appendingPathComponent("engines", isDirectory: true))
            trashIfSafe(D3DMetalDetector.vermutLibraryURL(appSupport: appSupport))
        }

        if plan.caches.isSelected {
            trashIfSafe(appSupport.appendingPathComponent("cache", isDirectory: true))
        }

        guard fullDataWipe else { return }

        if let remaining = try? fileManager.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in remaining {
                trashIfSafe(url)
            }
        }

        let stillThere = (try? fileManager.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        if stillThere.isEmpty {
            trashIfSafe(appSupport)
        }
    }

    /// Finder Trash on macOS; `removeItem` on Linux CI.
    private static func trashURL(_ url: URL, fileManager: FileManager) throws {
        #if canImport(Darwin)
        var resulting: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resulting)
        #else
        try fileManager.removeItem(at: url)
        #endif
    }
}
