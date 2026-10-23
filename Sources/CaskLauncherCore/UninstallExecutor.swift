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
        /// When true, schedule a detached helper to trash the .app after this PID exits.
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
                if let reason = UninstallPathPolicy.validateForRemoval(
                    appURL,
                    allowedPrefixes: allowed,
                    home: options.home
                ) {
                    let item = UninstallItemResult(
                        targetID: target.id,
                        displayName: target.displayName,
                        byteCount: target.byteCount,
                        outcome: .skipped,
                        message: reason,
                        revealURL: appURL
                    )
                    results.append(item)
                    progress?(.finished(item))
                    continue
                }
                if options.scheduleAppHelper {
                    let scheduled = scheduleDetachedAppTrash(
                        appURL: appURL,
                        afterPID: options.currentPID,
                        fileManager: options.fileManager
                    )
                    if scheduled {
                        deferredApp = appURL
                        let item = UninstallItemResult(
                            targetID: target.id,
                            displayName: target.displayName,
                            byteCount: target.byteCount,
                            outcome: .deferredApp,
                            message: "after quitting",
                            revealURL: appURL
                        )
                        results.append(item)
                        removedBytes += target.byteCount
                        progress?(.finished(item))
                    } else {
                        let item = UninstallItemResult(
                            targetID: target.id,
                            displayName: target.displayName,
                            byteCount: target.byteCount,
                            outcome: .failed,
                            message: "Vermut doesn't have permission to move Vermut.app to the Trash. Drag it to the Trash from Finder.",
                            revealURL: appURL
                        )
                        results.append(item)
                        progress?(.finished(item))
                    }
                } else {
                    // Test / dry path: try trash immediately.
                    let item = trashURLs(
                        target.urls,
                        target: target,
                        allowed: allowed,
                        home: options.home,
                        fileManager: options.fileManager
                    )
                    results.append(item)
                    if item.outcome == .removed { removedBytes += target.byteCount }
                    progress?(.finished(item))
                }
                continue
            }

            if target.category == .preferences, options.clearUserDefaults {
                UserDefaults.standard.removePersistentDomain(
                    forName: UninstallPathPolicy.bundleIdentifier
                )
                UserDefaults.standard.synchronize()
            }

            // When every custom bottle is selected, trash `custom-bottles.json` once
            // with the first selected custom bottle target.
            var urls = target.urls
            if target.category == .bottles, case .custom = target.bottleID {
                let customs = plan.bottles.filter {
                    if case .custom = $0.bottleID { return true }
                    return false
                }
                let allCustomSelected = !customs.isEmpty && customs.allSatisfy(\.isSelected)
                let isFirstSelectedCustom = customs.first(where: \.isSelected)?.id == target.id
                if allCustomSelected && isFirstSelectedCustom {
                    let index = options.appSupportURL.appendingPathComponent(
                        CustomBottleStore.indexFileName
                    )
                    if options.fileManager.fileExists(atPath: index.path) {
                        urls.append(index)
                    }
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

        // Remove empty Vermut root if everything under it is gone.
        if !isCancelled() {
            removeEmptyAppSupportIfNeeded(
                plan: plan,
                appSupport: options.appSupportURL,
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
            // Special-case: if a bottle tree contains dosdevices/z:, trash the bottle root;
            // FileManager moves the symlink as a link. Still validate the root.
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
            // If the path is a symlink (including z:), trash the link node only.
            do {
                var resulting: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resulting)
                anyRemoved = true
            } catch {
                // Permission / in use
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
            // Partial success still counts as failed row with note.
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

    private static func removeEmptyAppSupportIfNeeded(
        plan: UninstallPlan,
        appSupport: URL,
        fileManager: FileManager
    ) {
        // Only when bottles are all selected (or none existed) and other categories selected.
        let bottlesOk = plan.bottles.isEmpty || plan.bottles.allSatisfy(\.isSelected)
        guard bottlesOk,
              plan.engines.isSelected,
              plan.caches.isSelected,
              plan.preferences.isSelected else { return }
        guard fileManager.fileExists(atPath: appSupport.path) else { return }
        let remaining = (try? fileManager.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        if remaining.isEmpty {
            var resulting: NSURL?
            try? fileManager.trashItem(at: appSupport, resultingItemURL: &resulting)
        }
    }

    /// Writes a tiny `/tmp` shell script that waits for PID exit then asks Finder to trash the app.
    @discardableResult
    public static func scheduleDetachedAppTrash(
        appURL: URL,
        afterPID: Int32,
        fileManager: FileManager = .default
    ) -> Bool {
        // Refuse obviously non-writable / foreign locations without trying.
        let path = appURL.path
        guard path.hasSuffix(".app") || appURL.pathExtension == "app" else { return false }
        if UninstallPathPolicy.isHardExcluded(appURL) { return false }

        let scriptName = "vermut-uninstall-\(afterPID).sh"
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(scriptName)
        let escapedApp = appURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        #!/bin/sh
        # Vermut uninstall helper — waits for the app PID, then moves the bundle to Trash via Finder.
        pid=\(afterPID)
        app="\(escapedApp)"
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
        /usr/bin/osascript -e "tell application \\"Finder\\" to delete (POSIX file \\"$app\\")" >/dev/null 2>&1
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
        // Detach: don't wait. Process must outlive Vermut.
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
