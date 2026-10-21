import Foundation

/// Row state for the Settings › Components › DXMT list.
public enum DXMTRowState: Equatable, Sendable {
    case available
    case downloading(progress: Double, receivedBytes: Int64?, totalBytes: Int64?)
    case installing
    case installed
    case `default`
    case inUse(label: String)
    case failed(message: String)
}

/// One DXMT release that can be listed, downloaded, or already installed.
public struct DXMTReleaseInfo: Equatable, Identifiable, Sendable {
    public var tag: String
    public var filename: String?
    public var url: URL?
    public var sha256: String?
    public var publishedAt: Date?
    public var releaseNotesURL: URL?
    public var isInstalled: Bool
    public var isDefault: Bool
    public var isLatest: Bool
    public var inUseLabel: String?
    public var rowState: DXMTRowState

    public var id: String { tag }

    public init(
        tag: String,
        filename: String? = nil,
        url: URL? = nil,
        sha256: String? = nil,
        publishedAt: Date? = nil,
        releaseNotesURL: URL? = nil,
        isInstalled: Bool = false,
        isDefault: Bool = false,
        isLatest: Bool = false,
        inUseLabel: String? = nil,
        rowState: DXMTRowState = .available
    ) {
        self.tag = tag
        self.filename = filename
        self.url = url
        self.sha256 = sha256
        self.publishedAt = publishedAt
        self.releaseNotesURL = releaseNotesURL
        self.isInstalled = isInstalled
        self.isDefault = isDefault
        self.isLatest = isLatest
        self.inUseLabel = inUseLabel
        self.rowState = rowState
    }
}

/// Side-by-side DXMT installs under `engines/dxmt/versions/<tag>/`, with an active/default pointer.
public final class DXMTVersionManager: @unchecked Sendable {
    public static let shared = DXMTVersionManager()

    /// Pinned first-launch default (LGPL baseline). Also the catalog fallback tag.
    public static let defaultVersionTag = "v0.80"

    /// How many older GitHub releases to keep in the UI besides the newest.
    public static let previousVersionsToShow = 5

    private let fileManager: FileManager
    private let stateFileName = "active-version"

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public var versionsRootURL: URL {
        PathManager.shared.enginesURL
            .appendingPathComponent("dxmt", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
    }

    public var stateURL: URL {
        PathManager.shared.enginesURL
            .appendingPathComponent("dxmt", isDirectory: true)
            .appendingPathComponent(stateFileName)
    }

    /// Currently selected default DXMT (global). Falls back to pinned tag.
    public var activeVersionTag: String? {
        get {
            guard let data = try? Data(contentsOf: stateURL),
                  let tag = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !tag.isEmpty else {
                return migrateLegacyFlatInstallIfNeeded()
            }
            return ComponentVersion.canonicalTag(tag)
        }
        set {
            let root = stateURL.deletingLastPathComponent()
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            if let newValue {
                try? ComponentVersion.canonicalTag(newValue).data(using: .utf8)?.write(to: stateURL, options: .atomic)
            } else {
                try? fileManager.removeItem(at: stateURL)
            }
        }
    }

    public func installURL(for tag: String) -> URL {
        versionsRootURL.appendingPathComponent(ComponentVersion.canonicalTag(tag), isDirectory: true)
    }

    /// Overlay root used by Wine / PathManager.
    public func activeOverlayURL() -> URL {
        if let tag = activeVersionTag {
            let url = installURL(for: tag)
            if OverlayLayout.resolve(installRoot: url, fileManager: fileManager)?.hasD3D11 == true {
                return url
            }
        }
        let legacy = PathManager.shared.enginesURL.appendingPathComponent("dxmt", isDirectory: true)
        if OverlayLayout.resolve(installRoot: legacy, fileManager: fileManager)?.hasD3D11 == true {
            return legacy
        }
        return installURL(for: Self.defaultVersionTag)
    }

    public func isInstalled(_ tag: String) -> Bool {
        OverlayLayout.resolve(installRoot: installURL(for: tag), fileManager: fileManager)?.hasD3D11 == true
    }

    public func installedVersions() -> [String] {
        guard let items = try? fileManager.contentsOfDirectory(
            at: versionsRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return items
            .filter { OverlayLayout.resolve(installRoot: $0, fileManager: fileManager)?.hasD3D11 == true }
            .map { ComponentVersion.canonicalTag($0.lastPathComponent) }
            .sorted { ComponentVersion.compare($0, $1) == .orderedDescending }
    }

    public func setActiveVersion(_ tag: String) throws {
        let canonical = ComponentVersion.canonicalTag(tag)
        guard isInstalled(canonical) else {
            throw EngineError.overlayNotFound("DXMT \(canonical)", installURL(for: canonical).path)
        }
        activeVersionTag = canonical
    }

    /// Removes an installed version. The current default cannot be removed until another is set.
    public func uninstallVersion(_ tag: String, defaultTag: String) throws {
        let canonical = ComponentVersion.canonicalTag(tag)
        let currentDefault = ComponentVersion.canonicalTag(defaultTag)
        if canonical == currentDefault {
            throw DXMTVersionError.cannotRemoveDefault(canonical)
        }
        let url = installURL(for: canonical)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
        if activeVersionTag.map(ComponentVersion.canonicalTag) == canonical {
            if isInstalled(currentDefault) {
                activeVersionTag = currentDefault
            } else if let fallback = installedVersions().first {
                activeVersionTag = fallback
            } else {
                activeVersionTag = nil
            }
        }
    }

    public func markInstalled(tag: String, asActive: Bool = true) {
        let canonical = ComponentVersion.canonicalTag(tag)
        if asActive || activeVersionTag == nil {
            activeVersionTag = canonical
        }
    }

    /// Trims a remote list to newest + `previousVersionsToShow` older tags, always keeping `defaultTag` and `installed`.
    public func visibleRemoteTags(
        from remote: [ResolvedComponent],
        defaultTag: String,
        installed: [String]
    ) -> [ResolvedComponent] {
        let sorted = remote.sorted {
            ComponentVersion.compare($0.version, $1.version) == .orderedDescending
        }
        let keepInstalled = Set(installed.map(ComponentVersion.canonicalTag))
        let defaultCanonical = ComponentVersion.canonicalTag(defaultTag)
        var kept: [ResolvedComponent] = []
        var seen = Set<String>()
        for (index, component) in sorted.enumerated() {
            let tag = ComponentVersion.canonicalTag(component.version)
            let withinWindow = index <= Self.previousVersionsToShow
            let mustKeep = tag == defaultCanonical || keepInstalled.contains(tag)
            guard withinWindow || mustKeep else { continue }
            if seen.insert(tag).inserted {
                kept.append(component)
            }
        }
        if !seen.contains(defaultCanonical),
           let fallback = remote.first(where: {
               ComponentVersion.canonicalTag($0.version) == defaultCanonical
           }) ?? (defaultCanonical == ComponentCatalog.dxmtFallback.version
                  ? ComponentCatalog.dxmtFallback : nil) {
            kept.append(fallback)
        }
        return kept.sorted {
            ComponentVersion.compare($0.version, $1.version) == .orderedDescending
        }
    }

    /// Builds the UI list from GitHub + local installs.
    public func mergeCatalog(
        remote: [ResolvedComponent],
        installed: [String]? = nil,
        defaultTag: String,
        inUseLabels: [String: String] = [:],
        downloading: [String: DXMTRowState] = [:]
    ) -> [DXMTReleaseInfo] {
        let installedTags = (installed ?? installedVersions()).map(ComponentVersion.canonicalTag)
        let installedSet = Set(installedTags)
        let defaultCanonical = ComponentVersion.canonicalTag(defaultTag)
        let trimmed = visibleRemoteTags(from: remote, defaultTag: defaultTag, installed: installedTags)
        let latestTag = trimmed.first.map { ComponentVersion.canonicalTag($0.version) }

        var byTag: [String: DXMTReleaseInfo] = [:]
        for component in trimmed {
            let tag = ComponentVersion.canonicalTag(component.version)
            let isDef = tag == defaultCanonical
            let isInst = installedSet.contains(tag)
            let state: DXMTRowState
            if let transient = downloading[tag] {
                state = transient
            } else if isDef {
                state = .default
            } else if let label = inUseLabels[tag] {
                state = .inUse(label: label)
            } else if isInst {
                state = .installed
            } else {
                state = .available
            }
            byTag[tag] = DXMTReleaseInfo(
                tag: tag,
                filename: component.filename,
                url: component.url,
                sha256: component.sha256,
                releaseNotesURL: URL(string: "https://github.com/3Shain/dxmt/releases/tag/\(tag)"),
                isInstalled: isInst,
                isDefault: isDef,
                isLatest: tag == latestTag,
                inUseLabel: inUseLabels[tag],
                rowState: state
            )
        }

        for tag in installedSet where byTag[tag] == nil {
            let isDef = tag == defaultCanonical
            byTag[tag] = DXMTReleaseInfo(
                tag: tag,
                releaseNotesURL: URL(string: "https://github.com/3Shain/dxmt/releases/tag/\(tag)"),
                isInstalled: true,
                isDefault: isDef,
                isLatest: tag == latestTag,
                inUseLabel: inUseLabels[tag],
                rowState: isDef ? .default : (inUseLabels[tag].map { .inUse(label: $0) } ?? .installed)
            )
        }

        if byTag[defaultCanonical] == nil {
            let fallback = ComponentCatalog.dxmtFallback
            byTag[defaultCanonical] = DXMTReleaseInfo(
                tag: defaultCanonical,
                filename: fallback.filename,
                url: fallback.url,
                sha256: fallback.sha256,
                releaseNotesURL: URL(string: "https://github.com/3Shain/dxmt/releases/tag/\(defaultCanonical)"),
                isInstalled: installedSet.contains(defaultCanonical),
                isDefault: true,
                isLatest: defaultCanonical == latestTag,
                rowState: .default
            )
        }

        return byTag.values.sorted {
            ComponentVersion.compare($0.tag, $1.tag) == .orderedDescending
        }
    }

    /// Newer-than-default suggestion (info, never forced).
    public func newerThanDefault(
        in releases: [DXMTReleaseInfo],
        defaultTag: String
    ) -> DXMTReleaseInfo? {
        let current = ComponentVersion.canonicalTag(defaultTag)
        return releases.first {
            $0.isLatest && ComponentVersion.compare($0.tag, current) == .orderedDescending
        }
    }

    @discardableResult
    public func migrateLegacyFlatInstallIfNeeded() -> String? {
        let legacyRoot = PathManager.shared.enginesURL.appendingPathComponent("dxmt", isDirectory: true)
        let versionsDir = versionsRootURL
        guard OverlayLayout.resolve(installRoot: legacyRoot, fileManager: fileManager)?.hasD3D11 == true else {
            return nil
        }
        if !installedVersions().isEmpty {
            return activeVersionTag
        }
        let destination = installURL(for: Self.defaultVersionTag)
        if OverlayLayout.resolve(installRoot: destination, fileManager: fileManager)?.hasD3D11 != true {
            try? fileManager.createDirectory(at: versionsDir, withIntermediateDirectories: true)
            let skip = Set(["versions", stateFileName])
            if let items = try? fileManager.contentsOfDirectory(at: legacyRoot, includingPropertiesForKeys: nil) {
                try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                for item in items where !skip.contains(item.lastPathComponent) {
                    let dest = destination.appendingPathComponent(item.lastPathComponent)
                    if fileManager.fileExists(atPath: dest.path) { continue }
                    try? fileManager.moveItem(at: item, to: dest)
                }
            }
        }
        if OverlayLayout.resolve(installRoot: destination, fileManager: fileManager)?.hasD3D11 == true {
            activeVersionTag = Self.defaultVersionTag
            return Self.defaultVersionTag
        }
        return nil
    }
}

public enum DXMTVersionError: LocalizedError, Sendable {
    case cannotRemoveDefault(String)

    public var errorDescription: String? {
        switch self {
        case .cannotRemoveDefault(let tag):
            return "Set another default before removing DXMT \(tag)."
        }
    }
}
