import SwiftUI
import CaskLauncherCore

/// Settings › Wine Engines — download Gcenx staging/devel on demand.
struct WineEnginesSettingsSection: View {
    @StateObject private var model = WineEnginesViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s4) {
            Text("Wine Engines")
                .font(VermutType.headline)
            Text("Vermut Wine is the default. Gcenx WineHQ Staging and Devel download on demand and can be selected per bottle.")
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if !model.gstreamer.isPresent {
                HStack(alignment: .top, spacing: VermutSpace.s3) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.Vermut.warning)
                    VStack(alignment: .leading, spacing: VermutSpace.s1) {
                        Text(model.gstreamer.userFacingMessage ?? GStreamerProbe.missingMessage)
                            .font(VermutType.body)
                            .foregroundStyle(Color.Vermut.warningSubtleForeground)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(GStreamerProbe.installHint)
                            .font(VermutType.captionRegular)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                            .lineSpacing(2)
                    }
                }
                .padding(VermutSpace.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.Vermut.warningSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous)
                        .strokeBorder(Color.Vermut.warningBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.errorSubtleForeground)
            }

            VStack(spacing: 0) {
                ForEach(model.rows) { row in
                    engineRow(row)
                    if row.id != model.rows.last?.id {
                        Rectangle().fill(Color.Vermut.border).frame(height: 1)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous)
                    .strokeBorder(Color.Vermut.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous))

            Text("Changes apply the next time you open a store. Running sessions are not interrupted.")
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.mutedForeground)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .onAppear { model.refresh() }
        .alert(
            model.pendingDownload.map { model.confirmSheetTitle(for: $0) } ?? "Download engine?",
            isPresented: Binding(
                get: { model.pendingDownload != nil },
                set: { if !$0 { model.cancelPendingDownload() } }
            )
        ) {
            Button("Download") { model.confirmPendingDownload() }
            Button("Cancel", role: .cancel) { model.cancelPendingDownload() }
        } message: {
            if let engine = model.pendingDownload {
                Text(model.confirmSheetMessage(for: engine))
            }
        }
    }

    private func engineRow(_ row: WineEngineRow) -> some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            HStack(alignment: .firstTextBaseline, spacing: VermutSpace.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(row.engine.userFacingName)")
                        .font(VermutType.bodyEmphasis)
                    Text(row.engine.subtitle)
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                }
                Spacer(minLength: VermutSpace.s2)
                statusBadge(row)
            }

            switch row.state {
            case .downloading(let progress):
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                HStack {
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                    Spacer()
                    Button("Cancel") { model.cancelDownload() }
                        .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
                }
            case .available:
                HStack {
                    Spacer()
                    Button("Download") { model.requestDownload(row.engine) }
                        .buttonStyle(VermutButtonStyle(kind: .primary, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
                        .disabled(model.busyEngine != nil)
                }
            case .failed(let message):
                Text(message)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.errorSubtleForeground)
                Button("Retry download") { model.startDownload(row.engine) }
                    .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
            default:
                EmptyView()
            }

            if row.engine.requiresGStreamer, !model.gstreamer.isPresent {
                Text("Optional: install GStreamer for multimedia support.")
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
            }
        }
        .padding(VermutSpace.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.engine.userFacingName), \(accessibilityState(row))")
    }

    @ViewBuilder
    private func statusBadge(_ row: WineEngineRow) -> some View {
        switch row.state {
        case .included:
            VermutBadge(kind: .success, text: "Included", showsDot: true)
        case .installed:
            VermutBadge(kind: .success, text: "Installed", showsDot: true)
        case .available(let bytes):
            let label = bytes.map { "Download · \(WineEnginesViewModel.formatBytes($0))" } ?? "Download"
            VermutBadge(kind: .neutral, text: label)
        case .downloading:
            VermutBadge(kind: .info, text: "Downloading")
        case .failed:
            VermutBadge(kind: .error, text: "Failed")
        }
    }

    private func accessibilityState(_ row: WineEngineRow) -> String {
        switch row.state {
        case .included: return "included"
        case .installed: return "installed"
        case .available: return "available to download"
        case .downloading(let p): return "downloading \(Int(p * 100)) percent"
        case .failed: return "download failed"
        }
    }
}
