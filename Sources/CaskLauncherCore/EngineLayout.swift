import Foundation

/// On-disk layout of a Gcenx Wine `.app` (or a flat `bin/wine` tree).
public struct EngineLayout: Equatable, Sendable {
    public let installRoot: URL
    public let wineRoot: URL
    public let wineExecutable: URL
    public let wineserverExecutable: URL
    public let wineLibDir: URL
    public let windows64Dir: URL?
    public let windows32Dir: URL?
    public let unix64Dir: URL?

    public var binDir: URL {
        wineRoot.appendingPathComponent("bin")
    }

    public var wine64Executable: URL? {
        let candidates = [
            binDir.appendingPathComponent("wine64"),
            wineExecutable.deletingLastPathComponent().appendingPathComponent("wine64"),
            installRoot.appendingPathComponent("Contents/MacOS/wine64")
        ]
        var seen = Set<String>()
        for url in candidates {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            if FileManager.default.fileExists(atPath: path) {
                return url
            }
        }
        return nil
    }

    /// Win64 launchers (Epic) need `wine64` on Gcenx Staging; `wine` may be the 32-bit loader.
    public func launcherBinary(forWindowsExecutable windowsExecutable: URL) -> URL {
        if StoreExecutable.isWin64(windowsExecutable), let wine64 = wine64Executable {
            return wine64
        }
        return wineExecutable
    }

    /// Grapple-wine ships DXMT next to the engine (`share/grapple/dxmt`).
    public var bundledDXMTRoot: URL {
        wineRoot.appendingPathComponent("share/grapple/dxmt")
    }

    public func bundledDXMTOverlay(fileManager: FileManager = .default) -> OverlayLayout? {
        OverlayLayout.resolve(installRoot: bundledDXMTRoot, fileManager: fileManager)
    }

    public static func resolve(
        installRoot: URL,
        fileManager: FileManager = .default
    ) -> EngineLayout? {
        guard let wineRoot = findWineRoot(installRoot: installRoot, fileManager: fileManager),
              let wineExecutable = wineBinary(inWineRoot: wineRoot, installRoot: installRoot, fileManager: fileManager),
              let wineserver = firstExisting(
                [
                    wineRoot.appendingPathComponent("bin/wineserver"),
                    installRoot.appendingPathComponent("bin/wineserver")
                ],
                fileManager: fileManager
              )
        else {
            return nil
        }

        let libDir = wineRoot.appendingPathComponent("lib/wine")
        return EngineLayout(
            installRoot: installRoot,
            wineRoot: wineRoot,
            wineExecutable: wineExecutable,
            wineserverExecutable: wineserver,
            wineLibDir: libDir,
            windows64Dir: existingDir(libDir.appendingPathComponent("x86_64-windows"), fileManager),
            windows32Dir: existingDir(libDir.appendingPathComponent("i386-windows"), fileManager),
            unix64Dir: existingDir(libDir.appendingPathComponent("x86_64-unix"), fileManager)
        )
    }

    static func findWineRoot(installRoot: URL, fileManager: FileManager) -> URL? {
        var candidates: [URL] = [
            installRoot.appendingPathComponent("grapple-wine"),
            installRoot.appendingPathComponent("Contents/Resources/wine")
        ]

        if let items = try? fileManager.contentsOfDirectory(
            at: installRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for item in items where item.pathExtension == "app" {
                candidates.append(item.appendingPathComponent("Contents/Resources/wine"))
            }
        }

        candidates.append(installRoot)

        for root in candidates {
            if binWine(in: root, fileManager: fileManager) != nil {
                return root
            }
        }

        return findDirectoryContainingBinWine(from: installRoot, fileManager: fileManager)
    }

    static func binWine(in wineRoot: URL, fileManager: FileManager) -> URL? {
        firstExisting(
            [
                wineRoot.appendingPathComponent("bin/wine"),
                wineRoot.appendingPathComponent("bin/wine64")
            ],
            fileManager: fileManager
        )
    }

    static func wineBinary(
        inWineRoot wineRoot: URL,
        installRoot: URL,
        fileManager: FileManager
    ) -> URL? {
        if let binary = binWine(in: wineRoot, fileManager: fileManager) {
            return binary
        }

        var macOSWine: [URL] = [
            installRoot.appendingPathComponent("Contents/MacOS/wine")
        ]
        if let items = try? fileManager.contentsOfDirectory(at: installRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in items where item.pathExtension == "app" {
                macOSWine.append(item.appendingPathComponent("Contents/MacOS/wine"))
            }
        }
        return firstExisting(macOSWine, fileManager: fileManager)
    }

    private static func findDirectoryContainingBinWine(from root: URL, fileManager: FileManager) -> URL? {
        var pending: [(URL, Int)] = [(root, 0)]
        while !pending.isEmpty {
            let (dir, depth) = pending.removeFirst()
            if depth > 6 { continue }
            let wine = dir.appendingPathComponent("bin/wine")
            let wine64 = dir.appendingPathComponent("bin/wine64")
            if fileManager.fileExists(atPath: wine.path) || fileManager.fileExists(atPath: wine64.path) {
                return dir
            }
            guard let children = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue {
                    pending.append((child, depth + 1))
                }
            }
        }
        return nil
    }
}

/// DXMT / DXVK overlay: a folder that contains `x86_64-windows` / `i386-windows` / `x86_64-unix`.
public struct OverlayLayout: Equatable, Sendable {
    public let root: URL
    public let windows64Dir: URL?
    public let windows32Dir: URL?
    public let unix64Dir: URL?

    public var hasD3D11: Bool {
        d3d11URL != nil
    }

    public var hasDXGI: Bool {
        dxgiURL != nil
    }

    public var d3d11URL: URL? {
        windowsDLL("d3d11.dll")
    }

    /// DXVK-macOS 1.10.3 x64 ships `dxgi.dll`; the builtin/repack overlay does not.
    public var dxgiURL: URL? {
        windowsDLL("dxgi.dll")
    }

    /// Copy a DLL into the 64-bit overlay dir (`x86_64-windows` or `x64`).
    public func installWindowsDLL(
        _ source: URL,
        named name: String,
        fileManager: FileManager = .default
    ) throws {
        let dir = windows64Dir ?? root.appendingPathComponent("x64", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.copyItem(at: source, to: dest)
    }

    public func windowsDLL(_ name: String, fileManager: FileManager = .default) -> URL? {
        for dir in windows64SearchDirectories(fileManager: fileManager) + windows32SearchDirectories(fileManager: fileManager) {
            let dll = dir.appendingPathComponent(name)
            if fileManager.fileExists(atPath: dll.path) {
                return dll
            }
        }
        return nil
    }

    /// DXVK-macOS ships `x64/` (and the builtin pack uses `x86_64-windows/`). Search both.
    public func windows64SearchDirectories(fileManager: FileManager = .default) -> [URL] {
        Self.existingDirs(
            named: ["x86_64-windows", "x64", "x86_64"],
            under: root,
            preferring: windows64Dir,
            fileManager: fileManager
        )
    }

    public func windows32SearchDirectories(fileManager: FileManager = .default) -> [URL] {
        Self.existingDirs(
            named: ["i386-windows", "x32", "i386"],
            under: root,
            preferring: windows32Dir,
            fileManager: fileManager
        )
    }

    public static func resolve(
        installRoot: URL,
        fileManager: FileManager = .default
    ) -> OverlayLayout? {
        let roots = overlayRootCandidates(installRoot: installRoot, fileManager: fileManager)
        for root in roots {
            let win64 = existingDir(root.appendingPathComponent("x86_64-windows"), fileManager)
                ?? existingDir(root.appendingPathComponent("x64"), fileManager)
                ?? existingDir(root.appendingPathComponent("x86_64"), fileManager)
            let win32 = existingDir(root.appendingPathComponent("i386-windows"), fileManager)
                ?? existingDir(root.appendingPathComponent("x32"), fileManager)
                ?? existingDir(root.appendingPathComponent("i386"), fileManager)
            let unix64 = existingDir(root.appendingPathComponent("x86_64-unix"), fileManager)
            if win64 != nil || win32 != nil || unix64 != nil {
                return OverlayLayout(
                    root: root,
                    windows64Dir: win64,
                    windows32Dir: win32,
                    unix64Dir: unix64
                )
            }
        }
        return nil
    }

    private static func existingDirs(
        named names: [String],
        under root: URL,
        preferring preferred: URL?,
        fileManager: FileManager
    ) -> [URL] {
        var dirs: [URL] = []
        func add(_ url: URL?) {
            guard let url, existingDir(url, fileManager) != nil else { return }
            let path = url.standardizedFileURL.path
            if dirs.contains(where: { $0.standardizedFileURL.path == path }) { return }
            dirs.append(url.standardizedFileURL)
        }
        add(preferred)
        for name in names {
            add(root.appendingPathComponent(name))
        }
        return dirs
    }

    /// Child folder names that must never be treated as nested overlay roots.
    /// `engines/dxmt/versions/<tag>/` lives under the DXMT store directory.
    private static let skippedOverlayChildNames: Set<String> = ["versions"]

    private static func overlayRootCandidates(installRoot: URL, fileManager: FileManager) -> [URL] {
        var roots = [installRoot]
        if let items = try? fileManager.contentsOfDirectory(
            at: installRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for item in items {
                if skippedOverlayChildNames.contains(item.lastPathComponent) { continue }
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    roots.append(item)
                }
            }
        }
        return roots
    }
}

func existingDir(_ url: URL, _ fileManager: FileManager) -> URL? {
    var isDir: ObjCBool = false
    if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
        return url
    }
    return nil
}

func firstExisting(_ urls: [URL], fileManager: FileManager) -> URL? {
    urls.first { fileManager.fileExists(atPath: $0.path) }
}
