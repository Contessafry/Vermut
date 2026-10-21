import Foundation
import Combine

public enum WineEngineRowState: Equatable, Sendable {
    case included
    case installed
    case available(approxBytes: Int64?)
    case downloading(progress: Double)
    case failed(message: String)
}

public struct WineEngineRow: Identifiable, Equatable, Sendable {
    public var engine: WineEngine
    public var state: WineEngineRowState
    public var versionLabel: String
    public var updateAvailable: Bool

    public var id: String { engine.id }

    public init(
        engine: WineEngine,
        state: WineEngineRowState,
        versionLabel: String,
        updateAvailable: Bool = false
    ) {
        self.engine = engine
        self.state = state
        self.versionLabel = versionLabel
        self.updateAvailable = updateAvailable
    }
}

/// Settings › Wine Engines + shared download sheet used by bottle pickers.
@MainActor
public final class WineEnginesViewModel: ObservableObject {
    @Published public private(set) var rows: [WineEngineRow] = []
    @Published public private(set) var gstreamer: GStreamerStatus = GStreamerProbe.probe()
    @Published public private(set) var busyEngine: WineEngine?
    @Published public private(set) var busyProgress: Double = 0
    @Published public var errorMessage: String?
    @Published public var pendingDownload: WineEngine?

    /// Approximate download size shown before confirming (from fallback assets when known).
    public static let approximateDownloadBytes: [WineEngine: Int64] = [
        .staging: 210_000_000,
        .devel: 210_000_000
    ]

    private var downloadTask: Task<Void, Never>?

    public init() {
        refresh()
    }

    public func refresh() {
        gstreamer = GStreamerProbe.probe()
        rows = WineEngine.allCases.map { engine in
            let installed = EngineManager.shared.isEngineInstalled(engine)
            let fallback = ComponentCatalog.fallback(for: engine)
            let state: WineEngineRowState
            if engine == .grappleWine, installed {
                state = .included
            } else if installed {
                state = .installed
            } else if busyEngine == engine {
                state = .downloading(progress: busyProgress)
            } else {
                state = .available(approxBytes: Self.approximateDownloadBytes[engine])
            }
            return WineEngineRow(
                engine: engine,
                state: state,
                versionLabel: fallback.version,
                updateAvailable: false
            )
        }
    }

    public func requestDownload(_ engine: WineEngine) {
        guard engine != .grappleWine else { return }
        if EngineManager.shared.isEngineInstalled(engine) {
            refresh()
            return
        }
        pendingDownload = engine
    }

    public func confirmPendingDownload() {
        guard let engine = pendingDownload else { return }
        pendingDownload = nil
        startDownload(engine)
    }

    public func cancelPendingDownload() {
        pendingDownload = nil
    }

    public func startDownload(_ engine: WineEngine) {
        guard busyEngine == nil else { return }
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            await self?.runDownload(engine)
        }
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        busyEngine = nil
        busyProgress = 0
        refresh()
    }

    public func confirmSheetTitle(for engine: WineEngine) -> String {
        "Download \(engine.userFacingName)?"
    }

    public func confirmSheetMessage(for engine: WineEngine) -> String {
        let mb = Self.approximateDownloadBytes[engine].map { "About \(Self.formatBytes($0)). " } ?? ""
        return "\(mb)The bottle keeps using the current engine until the download finishes."
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    public static func pickerStatusLabel(for engine: WineEngine) -> String {
        if engine == .grappleWine {
            return EngineManager.shared.isEngineInstalled(engine) ? "Included" : "Download"
        }
        if EngineManager.shared.isEngineInstalled(engine) {
            return "Installed"
        }
        if let bytes = approximateDownloadBytes[engine] {
            return "Download · \(formatBytes(bytes))"
        }
        return "Download"
    }

    private func runDownload(_ engine: WineEngine) async {
        busyEngine = engine
        busyProgress = 0
        errorMessage = nil
        refresh()
        do {
            try await EngineManager.shared.downloadEngine(engine) { [weak self] value in
                Task { @MainActor in
                    self?.busyProgress = value
                    self?.refresh()
                }
            }
            if Task.isCancelled { return }
            busyEngine = nil
            busyProgress = 0
            refresh()
        } catch is CancellationError {
            busyEngine = nil
            busyProgress = 0
            refresh()
        } catch {
            errorMessage = "Engine not found. Reverting to Vermut Wine."
            busyEngine = nil
            busyProgress = 0
            refresh()
        }
    }
}
