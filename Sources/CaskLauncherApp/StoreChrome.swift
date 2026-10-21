import SwiftUI
import CaskLauncherCore

extension GameStore {
    var shortName: String {
        switch self {
        case .steam: return "Steam"
        case .epic: return "Epic Games"
        case .gog: return "GOG Galaxy"
        }
    }

    var openTitle: String {
        switch self {
        case .steam: return "Open Steam"
        case .epic: return "Open library"
        case .gog: return "Open GOG"
        }
    }

    var symbolName: String {
        switch self {
        case .steam: return "gamecontroller.fill"
        case .epic: return "flag.fill"
        case .gog: return "opticaldisc.fill"
        }
    }

    var tileColor: Color {
        // Explicit sRGB so tiles never go transparent if the catalog is missing.
        switch self {
        case .steam: return Color(.sRGB, red: 11 / 255, green: 26 / 255, blue: 43 / 255)
        case .epic: return Color(.sRGB, red: 18 / 255, green: 18 / 255, blue: 18 / 255)
        case .gog: return Color(.sRGB, red: 92 / 255, green: 45 / 255, blue: 145 / 255)
        }
    }

    var blurb: String {
        switch self {
        case .steam:
            return "Your Steam library, in its own bottle. Games launch straight from here."
        case .epic:
            return EpicStoreCopy.blurb
        case .gog:
            return "DRM-free classics and new releases. One click, no setup."
        }
    }

    var installingCopy: String {
        switch self {
        case .steam:
            return "Downloading the launcher and setting up the bottle."
        case .epic:
            return "Downloading Legendary and setting up the Epic bottle."
        case .gog:
            return "Downloading GOG Galaxy and setting up the bottle."
        }
    }
}

extension GraphicsBackend {
    var shortLabel: String {
        switch self {
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        case .d3dmetal: return "D3DMetal"
        case .wined3d: return "WineD3D"
        }
    }
}

extension WineEngine {
    var compactLabel: String { userFacingName }
}

enum BottleLabels {
    static func engineName(_ config: BottleConfiguration) -> String {
        let global = (try? ConfigurationManager.shared.loadConfiguration()) ?? AppConfiguration()
        StoreRecipe.effectiveEngine(config, global: global).value.userFacingName
    }

    static func graphicsName(_ config: BottleConfiguration, store: GameStore) -> String {
        let normalized = StoreRecipe.normalized(config, for: store)
        return GraphicsBackend(rawValue: normalized.graphicsBackend)?.shortLabel
            ?? GraphicsBackend.wined3d.shortLabel
    }

    static func engineLine(_ config: BottleConfiguration) -> String {
        "Engine: \(engineName(config))"
    }

    static func graphicsLine(_ config: BottleConfiguration, store: GameStore) -> String {
        "Graphics: \(graphicsName(config, store: store))"
    }
}

struct StoreStatusPresentation {
    var kind: VermutStatusKind
    var text: String
    var symbol: String?
    var showsDot: Bool
    var showsSpinner: Bool

    static func from(_ status: StoreStatus) -> StoreStatusPresentation {
        from(status, store: .steam, epicAccount: nil)
    }

    static func from(
        _ status: StoreStatus,
        store: GameStore,
        epicAccount: LegendaryAccount?
    ) -> StoreStatusPresentation {
        if store == .epic {
            switch status {
            case .running, .downloading, .installing, .error:
                break
            default:
                if let account = epicAccount, !account.displayName.isEmpty {
                    return StoreStatusPresentation(
                        kind: .success,
                        text: EpicStoreCopy.signedInBadge(account: account.displayName),
                        symbol: nil,
                        showsDot: true,
                        showsSpinner: false
                    )
                }
                return StoreStatusPresentation(
                    kind: .neutral,
                    text: EpicStoreCopy.signedOutBadge,
                    symbol: nil,
                    showsDot: false,
                    showsSpinner: false
                )
            }
        }
        switch status {
        case .running:
            return StoreStatusPresentation(
                kind: .success,
                text: "Running",
                symbol: nil,
                showsDot: true,
                showsSpinner: false
            )
        case .installed:
            return StoreStatusPresentation(
                kind: .success,
                text: "Installed",
                symbol: nil,
                showsDot: true,
                showsSpinner: false
            )
        case .downloading(let progress):
            let percent = Int((min(max(progress, 0), 0.99)) * 100)
            return StoreStatusPresentation(
                kind: .info,
                text: "Downloading · \(percent)%",
                symbol: "arrow.down.circle",
                showsDot: false,
                showsSpinner: true
            )
        case .installing(.settingUp):
            return StoreStatusPresentation(
                kind: .info,
                text: "Setting up…",
                symbol: "arrow.down.circle",
                showsDot: false,
                showsSpinner: true
            )
        case .installing(.updatingClient):
            return StoreStatusPresentation(
                kind: .info,
                text: "Updating…",
                symbol: "arrow.triangle.2.circlepath",
                showsDot: false,
                showsSpinner: true
            )
        case .installing(.awaitingWindow):
            return StoreStatusPresentation(
                kind: .warning,
                text: "Finish the installer window",
                symbol: "exclamationmark.triangle",
                showsDot: false,
                showsSpinner: false
            )
        case .error:
            return StoreStatusPresentation(
                kind: .error,
                text: "Download failed",
                symbol: "exclamationmark.circle",
                showsDot: false,
                showsSpinner: false
            )
        case .notInstalled:
            return StoreStatusPresentation(
                kind: .neutral,
                text: "Not installed",
                symbol: nil,
                showsDot: false,
                showsSpinner: false
            )
        }
    }
}

struct StoreLogoTile: View {
    let store: GameStore
    var size: CGFloat = 40

    private var radius: CGFloat {
        switch size {
        case ..<20: return VermutRadius.xs
        case ..<36: return VermutRadius.md
        case ..<48: return VermutRadius.lg
        default: return VermutRadius.xl
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(store.tileColor)
            BrandGlyphView(
                asset: store.brandAsset,
                size: size,
                inset: size * 0.18,
                templateForeground: .white
            )
            // 1pt white 12% ring on top so dark Epic tiles stay visible on zinc-900.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(store.rawValue)
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }

    static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}
