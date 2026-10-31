import Foundation

/// How Vermut translates x86_64 Windows code on Apple Silicon.
/// Rosetta 2 is the default: current Gcenx and Vermut Wine builds are `osx64`.
public enum X86EmulationMode: String, CaseIterable, Identifiable, Sendable {
    case rosetta
    case fex

    public var id: String { rawValue }

    public var userFacingName: String {
        switch self {
        case .rosetta: return "Rosetta 2"
        case .fex: return "FEX"
        }
    }

    public var subtitle: String {
        switch self {
        case .rosetta:
            return "Default. Translates the x86_64 Wine process (Gcenx / Vermut Wine)."
        case .fex:
            return "CrossOver-style ARM64 Wine + FEX. Needs an ARM64 engine that is not shipping yet."
        }
    }

    public static func resolved(from stored: String) -> X86EmulationMode {
        X86EmulationMode(rawValue: stored) ?? .rosetta
    }
}

public enum WineHostArchitecture: String, Sendable, Equatable {
    case x86_64
    case arm64
    case unknown
}

public struct FEXProbeResult: Equatable, Sendable {
    public var fexLibrariesFound: Bool
    public var fexRoot: URL?
    public var wineArchitecture: WineHostArchitecture
    public var wineURL: URL?

    public init(
        fexLibrariesFound: Bool,
        fexRoot: URL? = nil,
        wineArchitecture: WineHostArchitecture = .unknown,
        wineURL: URL? = nil
    ) {
        self.fexLibrariesFound = fexLibrariesFound
        self.fexRoot = fexRoot
        self.wineArchitecture = wineArchitecture
        self.wineURL = wineURL
    }

    /// CodeWeavers' Preview path: native ARM64 Wine plus FEX thunks.
    public var canRunFEX: Bool {
        fexLibrariesFound && wineArchitecture == .arm64
    }

    public var statusSummary: String {
        if canRunFEX {
            return "FEX libraries and ARM64 Wine are present. New bottles can use FEX."
        }
        if fexLibrariesFound, wineArchitecture != .arm64 {
            return "FEX libraries were found, but the installed Wine is not ARM64. Rosetta 2 stays in use."
        }
        return "No ARM64 Wine + FEX runtime is installed. Rosetta 2 stays in use."
    }
}

/// Detects a future ARM64 Wine + FEX layout. Gcenx `*-osx64` and current
/// grapple-wine builds are x86_64 and always go through Rosetta 2.
public enum FEXRuntime {
    public static let bundledDirectoryName = "fex"

    /// Filenames used by FEX-Emu / CrossOver Preview on disk.
    public static let markerFileNames = [
        "FEXInterpreter",
        "libFEXCore.dylib",
        "libFEXCore.so",
        "fex-emu",
        "libwow64fex.dll.so"
    ]

    public static func probe(
        enginesRoot: URL = PathManager.shared.enginesURL,
        wineURL: URL? = PathManager.shared.wineExecutable(engine: .grappleWine)
            ?? PathManager.shared.wineExecutable(engine: .staging)
            ?? PathManager.shared.wineExecutable(engine: .devel),
        fileManager: FileManager = .default
    ) -> FEXProbeResult {
        let fexRoot = findFEXRoot(enginesRoot: enginesRoot, fileManager: fileManager)
        let arch = wineArchitecture(at: wineURL)
        return FEXProbeResult(
            fexLibrariesFound: fexRoot != nil,
            fexRoot: fexRoot,
            wineArchitecture: arch,
            wineURL: wineURL
        )
    }

    public static func findFEXRoot(
        enginesRoot: URL,
        extraRoots: [URL] = defaultSearchRoots(),
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates = [enginesRoot.appendingPathComponent(bundledDirectoryName, isDirectory: true)]
        candidates.append(contentsOf: extraRoots)
        for root in candidates {
            if containsFEXMarkers(root, fileManager: fileManager) {
                return root
            }
        }
        return nil
    }

    public static func defaultSearchRoots() -> [URL] {
        [
            URL(fileURLWithPath: "/opt/fex-emu", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/opt/fex-emu", isDirectory: true),
            URL(fileURLWithPath: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/fex", isDirectory: true),
            URL(fileURLWithPath: "/Applications/CrossOver Preview.app/Contents/SharedSupport/CrossOver/lib64/fex", isDirectory: true)
        ]
    }

    public static func containsFEXMarkers(_ root: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: root.path) else { return false }
        for name in markerFileNames {
            if fileManager.fileExists(atPath: root.appendingPathComponent(name).path) {
                return true
            }
        }
        return false
    }

    /// Reads the Mach-O CPU type from the start of `wine`. Unknown on Linux tests.
    public static func wineArchitecture(at url: URL?) -> WineHostArchitecture {
        guard let url else { return .unknown }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8), data.count >= 8 else { return .unknown }
        let magic = data.prefix(4)
        let fatBE = Data([0xca, 0xfe, 0xba, 0xbe])
        let fatLE = Data([0xbe, 0xba, 0xfe, 0xca])
        if magic == fatBE || magic == fatLE {
            return .unknown
        }
        let cpu: UInt32
        if magic == Data([0xfe, 0xed, 0xfa, 0xcf]) || magic == Data([0xfe, 0xed, 0xfa, 0xce]) {
            cpu = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        } else if magic == Data([0xcf, 0xfa, 0xed, 0xfe]) || magic == Data([0xce, 0xfa, 0xed, 0xfe]) {
            cpu = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
        } else {
            return .unknown
        }
        // CPU_TYPE_X86_64 = 0x01000007, CPU_TYPE_ARM64 = 0x0100000c
        if cpu == 0x0100_0007 { return .x86_64 }
        if cpu == 0x0100_000c { return .arm64 }
        return .unknown
    }

    /// Env applied when the user asked for FEX *and* a usable runtime exists.
    public static func environment(probe: FEXProbeResult) -> [String: String] {
        guard probe.canRunFEX, let root = probe.fexRoot else { return [:] }
        return [
            "FEX_ROOTFS": root.path,
            "FEX_INTERPRETER": root.appendingPathComponent("FEXInterpreter").path
        ]
    }
}

public enum X86Emulation {
    /// Mutates a launch environment for the selected emulation mode.
    /// Falls back to the existing Rosetta Steam hints when FEX cannot run.
    public static func apply(
        to environment: inout [String: String],
        mode: X86EmulationMode,
        probe: FEXProbeResult,
        store: GameStore
    ) {
        let useFEX = mode == .fex && probe.canRunFEX
        if useFEX {
            environment["ROSETTA_ADVERTISE_AVX"] = nil
            for (key, value) in FEXRuntime.environment(probe: probe) {
                environment[key] = value
            }
            return
        }
        if store == .steam, environment["ROSETTA_ADVERTISE_AVX"] == nil {
            environment["ROSETTA_ADVERTISE_AVX"] = "1"
        }
    }
}
