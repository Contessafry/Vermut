import SwiftUI
import AppKit
import CaskLauncherCore

struct D3DMetalSettingsSection: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var model = D3DMetalViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            Text("D3DMetal (Apple Game Porting Toolkit)")
                .font(VermutType.headline)
            Text("Required for many DirectX 12 games. Apple’s licence means we cannot include it: you download it from Apple, and Vermut finds and uses it.")
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            statusCard
                .accessibilityLabel(model.accessibilityLabel)

            if case .notFound = model.presence {
                installGuideInline
            }
        }
        .onAppear {
            model.rescan()
            appState.hasD3DMetal = model.isUsable
        }
        .onChange(of: model.isUsable) { _, usable in
            appState.hasD3DMetal = usable
        }
        .sheet(isPresented: $model.showInstallGuide) {
            D3DMetalInstallGuideSheet(
                onPointToLocation: { pickFolder() },
                onClose: { model.showInstallGuide = false }
            )
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            HStack(spacing: VermutSpace.s2) {
                VermutBadge(kind: badgeKind, text: model.statusTitle, showsDot: model.isUsable)
                Spacer(minLength: VermutSpace.s2)
            }
            Text(model.detailText)
                .font(model.presence.rootURL == nil ? VermutType.body : VermutType.mono)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .textSelection(.enabled)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if case .unsupported = model.presence {
                Text("Version \(D3DMetalDetector.minimumVersion) or later is required. Download the latest from Apple.")
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.warningSubtleForeground)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.errorSubtleForeground)
            }

            HStack(spacing: VermutSpace.s2) {
                switch model.presence {
                case .notFound, .invalid:
                    Button("Point to location…") { pickFolder() }
                        .buttonStyle(VermutButtonStyle(kind: .outline))
                    Button("Installation guide") { model.showInstallGuide = true }
                        .buttonStyle(VermutButtonStyle(kind: .primary))
                case .found:
                    Button("Show in Finder") {
                        if let url = model.presence.rootURL {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .buttonStyle(VermutButtonStyle(kind: .outline))
                    Button("Search again") {
                        model.rescan()
                    }
                    .buttonStyle(VermutButtonStyle(kind: .outline))
                case .unsupported:
                    Button("Installation guide") { model.showInstallGuide = true }
                        .buttonStyle(VermutButtonStyle(kind: .outline))
                    Button("Point to location…") { pickFolder() }
                        .buttonStyle(VermutButtonStyle(kind: .outline))
                case .unavailableOnIntel:
                    EmptyView()
                }
            }
        }
        .padding(VermutSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous)
                .strokeBorder(Color.Vermut.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous))
        .disabled({
            if case .unavailableOnIntel = model.presence { return true }
            return false
        }())
    }

    private var installGuideInline: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            Text("Guide · 4 steps")
                .font(VermutType.headline)
            ForEach(Array(D3DMetalDetector.installGuideSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: VermutSpace.s3) {
                    Text("\(index + 1)")
                        .font(VermutType.caption)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .frame(width: 18, height: 18)
                        .background(Color.Vermut.secondary)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: VermutSpace.s1) {
                        Text(step.title)
                            .font(VermutType.body)
                            .foregroundStyle(Color.Vermut.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        if index == 0 {
                            Link("Open developer.apple.com", destination: D3DMetalDetector.developerOverviewURL)
                                .font(VermutType.callout)
                        }
                        if index == 3 {
                            Button("Point to location…") { pickFolder() }
                                .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
                        }
                    }
                }
            }
            Text("D3DMetal is Apple software under Apple’s licence. Vermut does not modify or redistribute it.")
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
        }
    }

    private var badgeKind: VermutStatusKind {
        switch model.presence {
        case .found: return .success
        case .unsupported, .unavailableOnIntel: return .warning
        case .invalid: return .error
        case .notFound: return .neutral
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use this folder"
        panel.message = "Select the GPTK redist/lib folder (contains external/D3DMetal.framework)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.applyPickedDirectory(url)
        if let path = model.presence.rootURL?.path {
            appState.configuration.d3dMetalLibraryPath = path
            appState.saveConfiguration()
        }
        appState.hasD3DMetal = model.isUsable
        appState.refreshBottleMetrics()
    }
}

struct D3DMetalInstallGuideSheet: View {
    var onPointToLocation: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s4) {
            Text("Install D3DMetal")
                .font(VermutType.title)
            ForEach(Array(D3DMetalDetector.installGuideSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: VermutSpace.s3) {
                    Text("\(index + 1).")
                        .font(VermutType.bodyEmphasis)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .frame(width: 24, alignment: .trailing)
                    Text(step.title)
                        .font(VermutType.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Link("Open developer downloads", destination: D3DMetalDetector.developerDownloadURL)
                .font(VermutType.bodyEmphasis)
            Text("D3DMetal is Apple software under Apple’s licence. Vermut does not modify or redistribute it.")
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.mutedForeground)
            HStack {
                Spacer()
                Button("Point to location…") {
                    onClose()
                    onPointToLocation()
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
                Button("Done", action: onClose)
                    .buttonStyle(VermutButtonStyle(kind: .primary))
            }
        }
        .padding(VermutSpace.s6)
        .frame(width: 520)
        .background(Color.Vermut.popover)
    }
}
