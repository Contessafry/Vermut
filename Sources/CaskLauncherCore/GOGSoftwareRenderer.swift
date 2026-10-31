import Foundation

/// Qt `QT_OPENGL=software` loads `opengl32sw.dll`. Galaxy does not ship it, so the
/// GOG recipe copies Mesa llvmpipe (WGL loader + `libgallium_wgl.dll`) beside
/// `GalaxyClient.exe`.
public enum GOGSoftwareRenderer {
    public static let requiredFilenames = ["opengl32sw.dll", "libgallium_wgl.dll"]
    public static let mesaOpenGLName = "opengl32.dll"
    public static let mesaGalliumName = "libgallium_wgl.dll"
    public static let qtSoftwareOpenGLName = "opengl32sw.dll"

    public static func missingRequired(
        beside executable: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        let dir = executable.deletingLastPathComponent()
        return requiredFilenames.filter {
            !fileManager.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }

    public static func isInstalled(
        beside executable: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        missingRequired(beside: executable, fileManager: fileManager).isEmpty
    }

    /// Directory that contains both Mesa WGL files (usually `x64/`).
    public static func mesaGLDirectory(
        in extracted: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        var queue = [extracted]
        var seen = 0
        while !queue.isEmpty {
            let dir = queue.removeFirst()
            seen += 1
            if seen > 40 { break }
            let opengl = dir.appendingPathComponent(mesaOpenGLName)
            let gallium = dir.appendingPathComponent(mesaGalliumName)
            if fileManager.fileExists(atPath: opengl.path),
               fileManager.fileExists(atPath: gallium.path) {
                return dir
            }
            guard let items = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for item in items {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    queue.append(item)
                }
            }
        }
        return nil
    }

    /// Copy Mesa `opengl32.dll` as Qt's `opengl32sw.dll` plus the Gallium WGL driver.
    public static func install(
        fromExtractedMesa root: URL,
        beside executable: URL,
        fileManager: FileManager = .default
    ) throws {
        guard let glDir = mesaGLDirectory(in: root, fileManager: fileManager) else {
            throw GOGSoftwareRendererError.mesaFilesMissing(root.path)
        }
        let dest = executable.deletingLastPathComponent()
        try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
        try replace(
            from: glDir.appendingPathComponent(mesaOpenGLName),
            to: dest.appendingPathComponent(qtSoftwareOpenGLName),
            fileManager: fileManager
        )
        try replace(
            from: glDir.appendingPathComponent(mesaGalliumName),
            to: dest.appendingPathComponent(mesaGalliumName),
            fileManager: fileManager
        )
    }

    public static func ensureInstalled(
        beside executable: URL,
        cacheURL: URL = PathManager.shared.cacheURL,
        fileManager: FileManager = .default
    ) async throws {
        if isInstalled(beside: executable, fileManager: fileManager) { return }
        let extracted = try await unpackMesa(cacheURL: cacheURL, fileManager: fileManager)
        try install(fromExtractedMesa: extracted, beside: executable, fileManager: fileManager)
        guard isInstalled(beside: executable, fileManager: fileManager) else {
            throw GOGSoftwareRendererError.mesaFilesMissing(extracted.path)
        }
    }

    public static func ensureInstalled(
        in prefixURL: URL,
        cacheURL: URL = PathManager.shared.cacheURL,
        fileManager: FileManager = .default
    ) async throws {
        guard let exe = StoreExecutable.resolve(
            in: prefixURL,
            store: .gog,
            fileManager: fileManager
        ) else { return }
        try await ensureInstalled(beside: exe, cacheURL: cacheURL, fileManager: fileManager)
    }

    private static func unpackMesa(
        cacheURL: URL,
        fileManager: FileManager
    ) async throws -> URL {
        let component = ComponentCatalog.mesaDistWinFallback
        let archive = cacheURL.appendingPathComponent(component.filename)
        try await DownloadClient.download(
            from: component.url,
            to: archive,
            expectedSHA256: component.sha256,
            progress: { _ in }
        )
        let extracted = cacheURL.appendingPathComponent(
            "mesa-dist-win-\(component.version)",
            isDirectory: true
        )
        if mesaGLDirectory(in: extracted, fileManager: fileManager) != nil {
            return extracted
        }
        try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        let seven = try await SevenZipTool.ensureExecutable(
            cacheURL: cacheURL,
            fileManager: fileManager
        )
        try SevenZipTool.extract(archive: archive, to: extracted, executable: seven)
        guard mesaGLDirectory(in: extracted, fileManager: fileManager) != nil else {
            throw GOGSoftwareRendererError.extractionFailed
        }
        return extracted
    }

    private static func replace(from: URL, to: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: to.path) {
            try fileManager.removeItem(at: to)
        }
        try fileManager.copyItem(at: from, to: to)
    }
}

public enum GOGSoftwareRendererError: LocalizedError, Sendable {
    case mesaFilesMissing(String)
    case sevenZipMissing
    case extractionFailed

    public var errorDescription: String? {
        switch self {
        case .mesaFilesMissing:
            return "GOG software renderer (opengl32sw) could not be installed. Mesa files were missing from the archive."
        case .sevenZipMissing:
            return "7-Zip (7zz) is required to unpack the GOG software renderer."
        case .extractionFailed:
            return "Failed to extract the GOG software renderer archive."
        }
    }
}

/// Host `7zz`/`7z` used only to unpack mesa-dist-win. Prefers PATH, then a cached extra.
public enum SevenZipTool {
    public static func extractArguments(archive: URL, destination: URL) -> [String] {
        ["x", "-y", "-o\(destination.path)", archive.path]
    }

    public static func findOnPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        let path = environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            for name in ["7zz", "7z"] {
                let url = URL(fileURLWithPath: String(directory)).appendingPathComponent(String(name))
                if fileManager.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    public static var hostFallback: ResolvedComponent {
        #if os(macOS)
        return ComponentCatalog.sevenZipMacFallback
        #else
        return ComponentCatalog.sevenZipLinuxFallback
        #endif
    }

    public static func ensureExecutable(
        cacheURL: URL,
        fileManager: FileManager = .default
    ) async throws -> URL {
        if let found = findOnPath(fileManager: fileManager) {
            return found
        }
        let component = hostFallback
        let archive = cacheURL.appendingPathComponent(component.filename)
        try await DownloadClient.download(
            from: component.url,
            to: archive,
            expectedSHA256: component.sha256,
            progress: { _ in }
        )
        let dest = cacheURL.appendingPathComponent("7zz-\(component.version)", isDirectory: true)
        if let existing = findBinary(in: dest, fileManager: fileManager) {
            return existing
        }
        try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xf", archive.path, "-C", dest.path]
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            throw GOGSoftwareRendererError.extractionFailed
        }
        if let found = findBinary(in: dest, fileManager: fileManager) {
            return found
        }
        throw GOGSoftwareRendererError.sevenZipMissing
    }

    public static func extract(archive: URL, to destination: URL, executable: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executable
        process.arguments = extractArguments(archive: archive, destination: destination)
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GOGSoftwareRendererError.extractionFailed
        }
    }

    private static func findBinary(in root: URL, fileManager: FileManager) -> URL? {
        let direct = root.appendingPathComponent("7zz")
        if fileManager.isExecutableFile(atPath: direct.path) {
            return direct
        }
        guard let items = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var visited = 0
        while let item = items.nextObject() as? URL {
            visited += 1
            if visited > 80 { break }
            if item.lastPathComponent == "7zz" || item.lastPathComponent == "7z" {
                if fileManager.isExecutableFile(atPath: item.path) {
                    return item
                }
            }
        }
        return nil
    }
}
