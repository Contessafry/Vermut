import Foundation

public final class EngineManager: @unchecked Sendable {
    public static let shared = EngineManager()

    private let fileManager = FileManager.default

    private init() {}

    public func isEngineInstalled(_ engine: WineEngine) -> Bool {
        PathManager.shared.wineExecutable(engine: engine) != nil
    }

    public func isAnyEngineInstalled() -> Bool {
        WineEngine.allCases.contains { isEngineInstalled($0) }
    }

    public func downloadEngine(_ engine: WineEngine, progress: @escaping @Sendable (Double) -> Void) async throws {
        let engineURL = PathManager.shared.engineURL(for: engine)
        if EngineLayout.resolve(installRoot: engineURL) != nil {
            progress(1.0)
            return
        }

        let component = await ComponentCatalog.resolveWine(engine)
        let downloadLocation = PathManager.shared.cacheURL.appendingPathComponent(component.filename)

        try await DownloadClient.download(
            from: component.url,
            to: downloadLocation,
            expectedSHA256: component.sha256,
            progress: progress
        )

        if fileManager.fileExists(atPath: engineURL.path) {
            try fileManager.removeItem(at: engineURL)
        }
        try fileManager.createDirectory(at: engineURL, withIntermediateDirectories: true)

        try await extractArchive(from: downloadLocation, to: engineURL, stripComponents: 0)

        guard let layout = EngineLayout.resolve(installRoot: engineURL) else {
            throw EngineError.wineBinaryNotFound(engineURL.path)
        }
        if engine.supportsDXMT, let overlay = layout.bundledDXMTOverlay() ?? OverlayLayout.resolve(installRoot: PathManager.shared.dxmtURL()) {
            try DXMTUnixLib.installIfNeeded(overlay: overlay, engine: layout)
        }

        try fileManager.removeItem(at: downloadLocation)
    }

    /// Downloads DXMT into a side-by-side version folder and optionally activates it.
    /// Default tag is `v0.80` (LGPL baseline).
    public func downloadDXMT(
        version tag: String? = nil,
        activate: Bool = true,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let manager = DXMTVersionManager.shared
        let preferred = tag.map(ComponentVersion.canonicalTag) ?? DXMTVersionManager.defaultVersionTag
        let dxmtURL = manager.installURL(for: preferred)
        if OverlayLayout.resolve(installRoot: dxmtURL)?.hasD3D11 == true {
            if activate {
                try manager.setActiveVersion(preferred)
            } else {
                manager.markInstalled(tag: preferred, asActive: manager.activeVersionTag == nil)
            }
            progress(1.0)
            return
        }

        let component = await ComponentCatalog.resolveDXMT(tag: preferred)
        let downloadLocation = PathManager.shared.cacheURL.appendingPathComponent(component.filename)

        try await DownloadClient.download(
            from: component.url,
            to: downloadLocation,
            expectedSHA256: component.sha256,
            progress: progress
        )

        if fileManager.fileExists(atPath: dxmtURL.path) {
            try fileManager.removeItem(at: dxmtURL)
        }
        try fileManager.createDirectory(at: dxmtURL, withIntermediateDirectories: true)

        try await extractArchive(from: downloadLocation, to: dxmtURL, stripComponents: 0)

        guard OverlayLayout.resolve(installRoot: dxmtURL)?.hasD3D11 == true else {
            throw EngineError.overlayNotFound("DXMT", dxmtURL.path)
        }

        if activate {
            try manager.setActiveVersion(ComponentVersion.canonicalTag(component.version))
        } else {
            manager.markInstalled(tag: component.version, asActive: manager.activeVersionTag == nil)
        }

        if let overlay = OverlayLayout.resolve(installRoot: manager.activeOverlayURL()),
           let layout = PathManager.shared.engineLayout(for: .grappleWine) {
            try DXMTUnixLib.installIfNeeded(overlay: overlay, engine: layout)
        }

        try fileManager.removeItem(at: downloadLocation)
    }

    public func setActiveDXMTVersion(_ tag: String) throws {
        try DXMTVersionManager.shared.setActiveVersion(tag)
        if let overlay = OverlayLayout.resolve(installRoot: DXMTVersionManager.shared.activeOverlayURL()),
           let layout = PathManager.shared.engineLayout(for: .grappleWine) {
            try DXMTUnixLib.installIfNeeded(overlay: overlay, engine: layout)
        }
    }

    public func downloadDXVK(progress: @escaping @Sendable (Double) -> Void) async throws {
        let dxvkURL = PathManager.shared.dxvkURL()
        var overlay = OverlayLayout.resolve(installRoot: dxvkURL)
        if overlay?.hasD3D11 == true, overlay?.hasDXGI == true {
            progress(1.0)
            return
        }

        if overlay?.hasD3D11 != true {
            let component = await ComponentCatalog.resolveDXVK()
            let downloadLocation = PathManager.shared.cacheURL.appendingPathComponent(component.filename)

            try await DownloadClient.download(
                from: component.url,
                to: downloadLocation,
                expectedSHA256: component.sha256,
                progress: progress
            )

            if fileManager.fileExists(atPath: dxvkURL.path) {
                try fileManager.removeItem(at: dxvkURL)
            }
            try fileManager.createDirectory(at: dxvkURL, withIntermediateDirectories: true)

            try await extractArchive(from: downloadLocation, to: dxvkURL, stripComponents: 0)
            overlay = OverlayLayout.resolve(installRoot: dxvkURL)
            guard overlay?.hasD3D11 == true else {
                throw EngineError.overlayNotFound("DXVK", dxvkURL.path)
            }
        }

        if overlay?.hasDXGI != true {
            try await installDxgiFromX64Pack(into: overlay, progress: progress)
        }
        progress(1.0)
    }

    /// The builtin/repack overlay has d3d11 but no dxgi. Merge `x64/dxgi.dll`
    /// from the verified 1.10.3 macOS tarball without replacing d3d11.
    func installDxgiFromX64Pack(
        into overlay: OverlayLayout?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let component = ComponentCatalog.dxvkFallback
        let downloadLocation = PathManager.shared.cacheURL.appendingPathComponent(component.filename)
        try await DownloadClient.download(
            from: component.url,
            to: downloadLocation,
            expectedSHA256: component.sha256,
            progress: progress
        )

        let unpack = PathManager.shared.cacheURL.appendingPathComponent("dxvk-x64-unpack", isDirectory: true)
        if fileManager.fileExists(atPath: unpack.path) {
            try fileManager.removeItem(at: unpack)
        }
        try fileManager.createDirectory(at: unpack, withIntermediateDirectories: true)
        try await extractArchive(from: downloadLocation, to: unpack, stripComponents: 0)

        guard let pack = OverlayLayout.resolve(installRoot: unpack),
              let dxgi = pack.windowsDLL("dxgi.dll") else {
            throw EngineError.overlayNotFound("DXVK dxgi", unpack.path)
        }
        guard let dest = overlay ?? OverlayLayout.resolve(installRoot: PathManager.shared.dxvkURL()) else {
            throw EngineError.overlayNotFound("DXVK", PathManager.shared.dxvkURL().path)
        }
        try dest.installWindowsDLL(dxgi, named: "dxgi.dll")
    }

    private func extractArchive(from archive: URL, to destination: URL, stripComponents: Int) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        var arguments = ["-xf", archive.path, "-C", destination.path]
        if stripComponents > 0 {
            arguments.append("--strip-components=\(stripComponents)")
        }
        process.arguments = arguments

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw EngineError.extractionFailed
        }
    }
}

public enum EngineError: LocalizedError {
    case invalidURL
    case downloadFailed
    case extractionFailed
    case wineBinaryNotFound(String)
    case overlayNotFound(String, String)
    case engineNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid download URL"
        case .downloadFailed:
            return "Download failed"
        case .extractionFailed:
            return "Failed to extract archive (tar exited with an error)"
        case .wineBinaryNotFound(let root):
            return "Wine was extracted to \(root) but no wine binary was found. Expected Vermut Wine or a Wine Staging/Devel layout."
        case .overlayNotFound(let name, let root):
            return "\(name) was extracted to \(root) but d3d11.dll was not found in an x86_64-windows or i386-windows folder."
        case .engineNotFound:
            return "Wine engine not found"
        }
    }
}
