import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Outcome for a single uninstall target.
public struct UninstallItemResult: Identifiable, Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable {
        case removed
        case failed
        case skipped
        case deferredApp // trashed by helper after quit
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
    public var deferredAppURL: URL?
    public var shouldQuit: Bool

    public init(
        results: [UninstallItemResult],
        removedByteCount: Int64,
        keptBottleCount: Int,
        keptBottleBytes: Int64,
        keptBottlesPath: URL?,
        deferredAppURL: URL?,
        shouldQuit: Bool
    ) {
        self.results = results
        self.removedByteCount = removedByteCount
        self.keptBottleCount = keptBottleCount
        self.keptBottleBytes = keptBottleBytes
        self.keptBottlesPath = keptBottlesPath
        self.deferredAppURL = deferredAppURL
        self.shouldQuit = shouldQuit
    }

    public var hasFailures: Bool {
        results.contains { $0.outcome == .failed || $0.outcome == .skipped }
    }

    public var failureResults: [UninstallItemResult] {
        results.filter { $0.outcome == .failed || $0.outcome == .skipped }
    }

    public var successResults: [UninstallItemResult] {
        results.filter { $0.outcome == .removed || $0.outcome == .deferredApp }
    }
}

/// Trashes selected Vermut data via `FileManager.trashItem`. Never follows Wine `z:` targets.
public enum UninstallExecutor {
    public struct Options: Sendable {
        public var appSupportURL: URL
        public var home: URL
        public var fileManager: FileManager
        public var clearUserDefaults: Bool
        /// When true, try trash then schedule a detached helper for the .app.
        public var scheduleAppHelper: Bool
        public var currentPID: Int32

        public init(
            appSupportURL: URL = PathManager.shared.appSupportURL,
            home: URL = FileManager.default.homeDirectoryForCurrentUser,
            fileManager: FileManager = .default,
            clearUserDefaults: Bool = true,
            scheduleAppHelper: Bool = true,
            currentPID: Int32 = ProcessInfo.processInfo.processIdentifier
        ) {
            self.appSupportURL = appSupportURL
            self.home = home
            self.fileManager = fileManager
            self.clearUserDefaults = clearUserDefaults
            self.scheduleAppHelper = scheduleAppHelper
            self.currentPID = currentPID
        }
    }

    public enum ProgressEvent: Sendable {
        case started(displayName: String, index: Int, total: Int)
        case finished(UninstallItemResult)
    }

    public enum AppRemovalResult: Sendable, Equatable {
        case trashedNow
        case deferredHelper
        case failed(message: String)
    }

    /// Removal order: logs → caches → engines → bottles → preferences → app.
    public static func orderedTargets(from plan: UninstallPlan) -> [UninstallTarget] {
        var ordered: [UninstallTarget] = []
        if plan.logs.isSelected { ordered.append(plan.logs) }
        if plan.caches.isSelected { ordered.append(plan.caches) }
        if plan.engines.isSelected { ordered.append(plan.engines) }
        ordered.append(contentsOf: plan.bottles.filter(\.isSelected))
        if plan.preferences.isSelected { ordered.append(plan.preferences) }
        if plan.app.isSelected { ordered.append(plan.app) }
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
            appBundle: plan.app.urls.first,
            home: options.home
        )
        let targets = orderedTargets(from: plan)
        var results: [UninstallItemResult] = []
        var removedBytes: Int64 = 0
        var deferredApp: URL?
        let total = max(targets.count, 1)

        for (index, target) in targets.enumerated() {
            if isCancelled() { break }
            progress?(.started(displayName: target.displayName, index: index + 1, total: total))

            if target.requiresDetachedAppRemoval {
                let appURL = target.urls.first ?? Bundle.main.bundleURL
                let (removal, item) = removeAppBundle(
                    appURL,
                    target: target,
                    allowed: allowed,
                    home: options.home,
                    scheduleHelper: options.scheduleAppHelper,
                    afterPID: options.currentPID,
                    fileManager: options.fileManager
                )
                results.append(item)
                if item.outcome == .removed || item.outcome == .deferredApp {
                    removedBytes += target.byteCount
                }
                if case .deferredHelper = removal {
                    deferredApp = appURL
                }
                progress?(.finished(item))
                continue
            }

            if target.category == .preferences, options.clearUserDefaults {
                UserDefaults.standard.removePersistentDomain(
                    forName: UninstallPathPolicy.bundleIdentifier
                )
                UserDefaults.standard.synchronize()
            }

            var urls = target.urls
            // When every bottle is selected, also ensure custom-bottles.json goes with bottles.
            if target.category == .bottles,
               plan.bottles.allSatisfy(\.isSelected),
               target.id == plan.bottles.first(where: \.isSelected)?.id {
                let index = options.appSupportURL.appendingPathComponent(
                    CustomBottleStore.indexFileName
                )
                if options.fileManager.fileExists(atPath: index.path) {
                    urls.append(index)
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
                : options.appSupportURL.appendingPathComponent("bottles", isDirectory: true),
            deferredAppURL: deferredApp,
            shouldQuit: deferredApp != nil || plan.app.isSelected
        )
    }

    // MARK: - App bundle

    /// Prefer live `trashItem` when writable; otherwise schedule a helper that `mv`s into `~/.Trash`
    /// (no Finder AppleEvents — Automation -1743).
    public static func removeAppBundle(
        _ appURL: URL,
        target: UninstallTarget,
        allowed: [URL],
        home: URL,
        scheduleHelper: Bool,
        afterPID: Int32,
        fileManager: FileManager
    ) -> (removal: AppRemovalResult, item: UninstallItemResult) {
        if let reason = UninstallPathPolicy.validateForRemoval(
            appURL,
            allowedPrefixes: allowed,
            home: home
        ) {
            return (
                .failed(message: reason),
                UninstallItemResult(
                    targetID: target.id,
                    displayName: target.displayName,
                    byteCount: target.byteCount,
                    outcome: .skipped,
                    message: reason,
                    revealURL: appURL
                )
            )
        }

        // 1) Try trash while still running (works when the bundle is writable / not locked).
        do {
            var resulting: NSURL?
            try fileManager.trashItem(at: appURL, resultingItemURL: &resulting)
            return (
                .trashedNow,
                UninstallItemResult(
                    targetID: target.id,
                    displayName: target.displayName,
                    byteCount: target.byteCount,
                    outcome: .removed,
                    message: nil,
                    revealURL: nil
                )
            )
        } catch {
            // Fall through to helper — common when the running binary locks the bundle.
        }

        guard scheduleHelper else {
            let message =
                "Vermut doesn't have permission to move Vermut.app to the Trash. Drag it to the Trash from Finder."
            return (
                .failed(message: message),
                UninstallItemResult(
                    targetID: target.id,
                    displayName: target.displayName,
                    byteCount: target.byteCount,
                    outcome: .failed,
                    message: message,
                    revealURL: appURL
                )
            )
        }

        if scheduleDetachedAppTrash(appURL: appURL, afterPID: afterPID, fileManager: fileManager) {
            return (
                .deferredHelper,
                UninstallItemResult(
                    targetID: target.id,
                    displayName: target.displayName,
                    byteCount: target.byteCount,
                    outcome: .deferredApp,
                    message: "after quitting",
                    revealURL: appURL
                )
            )
        }

        let message =
            "Vermut doesn't have permission to move Vermut.app to the Trash. Drag it to the Trash from Finder."
        return (
            .failed(message: message),
            UninstallItemResult(
                targetID: target.id,
                displayName: target.displayName,
                byteCount: target.byteCount,
                outcome: .failed,
                message: message,
                revealURL: appURL
            )
        )
    }

    // MARK: - Trash helpers

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
                var resulting: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resulting)
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
            var resulting: NSURL?
            try? fileManager.trashItem(at: url, resultingItemURL: &resulting)
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

        // Force-clean any remaining whitelist children (empty dirs, stray files).
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

    /// `/tmp` shell helper: wait for PID exit, then `mv` the .app into `~/.Trash` (no Finder AE).
    @discardableResult
    public static func scheduleDetachedAppTrash(
        appURL: URL,
        afterPID: Int32,
        fileManager: FileManager = .default
    ) -> Bool {
        guard appURL.pathExtension == "app" || appURL.path.hasSuffix(".app") else { return false }
        if UninstallPathPolicy.isHardExcluded(appURL) { return false }

        let scriptName = "vermut-uninstall-\(afterPID).sh"
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(scriptName)
        let escapedApp = shellEscape(appURL.path)
        let script = """
        #!/bin/sh
        # Vermut uninstall helper — wait for app PID, then move bundle into ~/.Trash (no Finder).
        pid=\(afterPID)
        app=\(escapedApp)
        i=0
        while kill -0 "$pid" 2>/dev/null; do
          i=$((i+1))
          if [ "$i" -gt 120 ]; then
            exit 1
          fi
          sleep 0.25
        done
        sleep 0.4
        if [ ! -e "$app" ]; then
          exit 0
        fi
        trash_dir="${HOME}/.Trash"
        /bin/mkdir -p "$trash_dir" 2>/dev/null
        base=$(/usr/bin/basename "$app")
        dest="$trash_dir/$base"
        n=1
        while [ -e "$dest" ]; do
          dest="$trash_dir/${base%.app} ${n}.app"
          n=$((n+1))
        done
        /bin/mv "$app" "$dest"
        exit $?
        """
        do {
            try script.data(using: .utf8)?.write(to: scriptURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
