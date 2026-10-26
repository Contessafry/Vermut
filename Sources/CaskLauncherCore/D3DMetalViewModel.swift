import Foundation
#if canImport(Combine)
import Combine
#endif

/// Observable surface for Settings › Components › D3DMetal.
@MainActor
public final class D3DMetalViewModel: ObservableObject {
    @Published public private(set) var result: D3DMetalDetectionResult
    @Published public var showInstallGuide = false
    @Published public var errorMessage: String?

    private var pathProvider: () -> String?
    private var pathWriter: (String?) -> Void

    public init(
        customPath: @escaping () -> String? = {
            ((try? ConfigurationManager.shared.loadConfiguration()) ?? AppConfiguration()).d3dMetalLibraryPath
        },
        setCustomPath: @escaping (String?) -> Void = { path in
            var config = (try? ConfigurationManager.shared.loadConfiguration()) ?? AppConfiguration()
            config.d3dMetalLibraryPath = path
            try? ConfigurationManager.shared.saveConfiguration(config)
        }
    ) {
        self.pathProvider = customPath
        self.pathWriter = setCustomPath
        self.result = D3DMetalDetector.detect(customPath: customPath())
    }

    public var presence: D3DMetalPresence { result.presence }

    public var isUsable: Bool { presence.isUsable }

    public var statusTitle: String {
        switch presence {
        case .notFound:
            return "Not found"
        case .found(let version, _):
            if let version { return "Found · \(version)" }
            return "Found"
        case .unsupported(let version, _):
            if let version { return "Unsupported version · \(version)" }
            return "Unsupported version"
        case .invalid:
            return "Error"
        case .unavailableOnIntel:
            return "Apple Silicon only"
        }
    }

    public var statusKindLabel: String {
        switch presence {
        case .notFound: return "neutral"
        case .found: return "success"
        case .unsupported, .unavailableOnIntel: return "warning"
        case .invalid: return "error"
        }
    }

    public var detailText: String {
        switch presence {
        case .notFound:
            return "We searched the usual locations."
        case .found(_, let root), .unsupported(_, let root):
            return root.path
        case .invalid(let reason):
            return reason
        case .unavailableOnIntel:
            return "D3DMetal only works on Macs with Apple Silicon."
        }
    }

    public var accessibilityLabel: String {
        switch presence {
        case .found(let version, _):
            return "D3DMetal, found" + (version.map { ", version \($0)" } ?? "")
        case .notFound:
            return "D3DMetal, not found"
        case .unsupported(let version, _):
            return "D3DMetal, unsupported version" + (version.map { " \($0)" } ?? "")
        case .invalid:
            return "D3DMetal, error"
        case .unavailableOnIntel:
            return "D3DMetal, unavailable on Intel"
        }
    }

    public func rescan() {
        errorMessage = nil
        result = D3DMetalDetector.detect(customPath: pathProvider())
    }

    public func applyPickedDirectory(_ url: URL) {
        errorMessage = nil
        let validation = D3DMetalDetector.validate(root: url)
        switch validation {
        case .found, .unsupported:
            pathWriter(validation.rootURL?.path ?? url.path)
            result = D3DMetalDetectionResult(presence: validation, searchedPaths: [url.path])
        case .invalid(let reason):
            errorMessage = reason
            result = D3DMetalDetectionResult(presence: validation, searchedPaths: [url.path])
        case .notFound, .unavailableOnIntel:
            errorMessage = "The selected folder does not contain D3DMetal.framework. Select the redist/lib folder."
            result = D3DMetalDetectionResult(presence: .invalid(reason: errorMessage!), searchedPaths: [url.path])
        }
    }

    public func clearCustomPath() {
        pathWriter(nil)
        rescan()
    }
}
