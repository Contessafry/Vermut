import Foundation
#if canImport(Combine)
import Combine
#endif

/// Observable surface for Settings › Components › DXMT.
@MainActor
public final class DXMTVersionsViewModel: ObservableObject {
    @Published public private(set) var releases: [DXMTReleaseInfo] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastRefresh: Date?
    @Published public private(set) var networkFailed = false
    @Published public private(set) var updateSuggestion: DXMTReleaseInfo?
    @Published public var errorMessage: String?
    @Published public private(set) var busyTag: String?
    @Published public private(set) var busyState: DXMTRowState?

    private let manager: DXMTVersionManager
    private var defaultTagProvider: () -> String
    private var defaultTagWriter: (String) -> Void
    private var downloadTask: Task<Void, Never>?

    public init(
        manager: DXMTVersionManager = .shared,
        defaultTag: @escaping () -> String = {
            ((try? ConfigurationManager.shared.loadConfiguration()) ?? AppConfiguration()).defaultDXMTVersion
        },
        setDefaultTag: @escaping (String) -> Void = { tag in
            var config = (try? ConfigurationManager.shared.loadConfiguration()) ?? AppConfiguration()
            config.defaultDXMTVersion = ComponentVersion.canonicalTag(tag)
            try? ConfigurationManager.shared.saveConfiguration(config)
        }
    ) {
        self.manager = manager
        self.defaultTagProvider = defaultTag
        self.defaultTagWriter = setDefaultTag
        refreshLocal()
    }

    public var footerText: String {
        let source = "github.com/3Shain/dxmt"
        guard let lastRefresh else {
            return "List from \(source)"
        }
        let minutes = max(0, Int(Date().timeIntervalSince(lastRefresh) / 60))
        let when: String
        if minutes < 1 {
            when = "just now"
        } else if minutes == 1 {
            when = "1 min ago"
        } else {
            when = "\(minutes) min ago"
        }
        return "List updated from \(source) · last check \(when)"
    }

    public func refreshLocal() {
        let defaultTag = defaultTagProvider()
        releases = manager.mergeCatalog(
            remote: [ComponentCatalog.dxmtFallback],
            defaultTag: defaultTag,
            downloading: busySnapshot()
        )
        updateSuggestion = manager.newerThanDefault(in: releases, defaultTag: defaultTag)
    }

    public func refreshFromNetwork() async {
        isLoading = true
        errorMessage = nil
        networkFailed = false
        defer { isLoading = false }
        let remote = await ComponentCatalog.listDXMTReleases()
        if remote.count == 1, remote[0] == ComponentCatalog.dxmtFallback {
            // Likely offline — keep installed + fallback, surface soft message.
            networkFailed = true
            errorMessage = "Could not reach GitHub. Showing installed versions."
        }
        lastRefresh = Date()
        let defaultTag = defaultTagProvider()
        releases = manager.mergeCatalog(
            remote: remote,
            defaultTag: defaultTag,
            downloading: busySnapshot()
        )
        updateSuggestion = manager.newerThanDefault(in: releases, defaultTag: defaultTag)
        // Persist default pointer for PathManager when missing.
        if manager.activeVersionTag == nil, manager.isInstalled(defaultTag) {
            try? manager.setActiveVersion(defaultTag)
        }
    }

    public func install(_ tag: String, makeDefault: Bool = true) {
        guard busyTag == nil else { return }
        let canonical = ComponentVersion.canonicalTag(tag)
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            await self?.runInstall(canonical, makeDefault: makeDefault)
        }
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        busyTag = nil
        busyState = nil
        refreshLocal()
    }

    public func setAsDefault(_ tag: String) {
        errorMessage = nil
        do {
            try EngineManager.shared.setActiveDXMTVersion(tag)
            defaultTagWriter(tag)
            refreshLocal()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func uninstall(_ tag: String) {
        errorMessage = nil
        do {
            try manager.uninstallVersion(tag, defaultTag: defaultTagProvider())
            refreshLocal()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func acceptUpdateSuggestion() {
        guard let updateSuggestion else { return }
        install(updateSuggestion.tag, makeDefault: true)
    }

    private func runInstall(_ tag: String, makeDefault: Bool) async {
        busyTag = tag
        busyState = .downloading(progress: 0, receivedBytes: nil, totalBytes: nil)
        errorMessage = nil
        refreshLocal()
        do {
            try await EngineManager.shared.downloadDXMT(version: tag, activate: makeDefault) { [weak self] value in
                Task { @MainActor in
                    self?.busyState = .downloading(progress: value, receivedBytes: nil, totalBytes: nil)
                    self?.refreshLocal()
                }
            }
            if Task.isCancelled { return }
            busyState = .installing
            refreshLocal()
            if makeDefault {
                defaultTagWriter(tag)
            }
            busyTag = nil
            busyState = nil
            await refreshFromNetwork()
        } catch is CancellationError {
            busyTag = nil
            busyState = nil
            refreshLocal()
        } catch let error as DownloadError {
            busyTag = tag
            switch error {
            case .checksumMismatch:
                busyState = .failed(message: "The checksum does not match. The file was discarded.")
            default:
                busyState = .failed(message: "Download failed. Check your connection and try again.")
            }
            errorMessage = busyState.flatMap {
                if case .failed(let message) = $0 { return message }
                return nil
            }
            refreshLocal()
            busyTag = nil
            busyState = nil
        } catch {
            busyState = .failed(message: "Install failed: invalid archive.")
            errorMessage = error.localizedDescription
            refreshLocal()
            busyTag = nil
            busyState = nil
        }
    }

    private func busySnapshot() -> [String: DXMTRowState] {
        guard let busyTag, let busyState else { return [:] }
        return [busyTag: busyState]
    }
}
