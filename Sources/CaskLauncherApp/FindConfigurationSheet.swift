import SwiftUI
import CaskLauncherCore

struct FindConfigurationSheet: View {
    let game: InstalledGame
    @EnvironmentObject var appState: AppState
    @ObservedObject var controller: FindConfigurationController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s4) {
            header
            thresholdRow
            progressBlock
            resultsList
            footer
        }
        .padding(VermutSpace.s5)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420)
        .background(Color.Vermut.background)
        .onAppear {
            if controller.phase == .idle {
                controller.prepare(
                    game: game,
                    appState: appState,
                    d3dMetalInstalled: appState.hasD3DMetal
                )
            }
        }
        .onDisappear {
            if controller.phase == .running {
                controller.stop(appState: appState)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            Text(String(localized: "Find configuration", comment: "Find configuration title"))
                .font(VermutType.headline)
                .foregroundStyle(Color.Vermut.foreground)
            Text(
                String(
                    localized: "Vermut will try Wine engines, graphics backends, Steam overlay, and a few launch options until \(game.name) stays running. Confirm the window yourself — a black screen can still look “alive”.",
                    comment: "Find configuration intro"
                )
            )
            .font(VermutType.captionRegular)
            .foregroundStyle(Color.Vermut.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var thresholdRow: some View {
        HStack {
            Text(String(localized: "Success wait", comment: "Find configuration threshold"))
                .font(VermutType.bodyEmphasis)
            Spacer()
            Picker("", selection: $controller.aliveThreshold) {
                Text("30s").tag(30.0)
                Text("45s").tag(45.0)
                Text("60s").tag(60.0)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
            .disabled(controller.isRunning)
        }
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            if controller.total > 0 {
                ProgressView(
                    value: Double(min(controller.currentIndex, controller.total)),
                    total: Double(max(controller.total, 1))
                )
                .tint(Color.Vermut.primary)
                Text(controller.progressLabel)
                    .font(VermutType.caption)
                    .foregroundStyle(Color.Vermut.mutedForeground)
            }
            if let combo = controller.currentCombo, controller.phase != .idle {
                Text(combo.displayLabel)
                    .font(VermutType.bodyEmphasis)
            }
            if !controller.statusMessage.isEmpty {
                Text(controller.statusMessage)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if controller.phase == .awaitingConfirmation {
                HStack(spacing: VermutSpace.s2) {
                    Button(String(localized: "Yes, it works", comment: "Find configuration confirm yes")) {
                        controller.confirmWorks(appState: appState)
                    }
                    .buttonStyle(VermutButtonStyle(kind: .primary))
                    Button(String(localized: "No, keep searching", comment: "Find configuration confirm no")) {
                        controller.rejectWorks(appState: appState)
                    }
                    .buttonStyle(VermutButtonStyle(kind: .outline))
                }
            }
            if controller.offerCompatReport {
                Button(String(localized: "Submit a compat report", comment: "Find configuration compat")) {
                    controller.submitCompatReport(appState: appState)
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
            }
        }
        .padding(VermutSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Vermut.secondary)
        .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            Text(String(localized: "Results", comment: "Find configuration results"))
                .font(VermutType.bodyEmphasis)
            if controller.attempts.isEmpty {
                Text(String(localized: "No attempts yet.", comment: "Find configuration empty results"))
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: VermutSpace.s2) {
                        ForEach(controller.attempts) { attempt in
                            resultRow(attempt)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 220)
            }
        }
    }

    private func resultRow(_ attempt: FindConfigurationAttempt) -> some View {
        HStack(alignment: .top, spacing: VermutSpace.s2) {
            Text(statusGlyph(attempt.outcome))
                .font(VermutType.caption)
                .foregroundStyle(statusColor(attempt.outcome))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(attempt.index). \(attempt.combo.displayLabel)")
                    .font(VermutType.callout)
                if !attempt.detail.isEmpty {
                    Text(attempt.detail)
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: VermutSpace.s2) {
            if controller.phase == .running {
                Button(String(localized: "Stop", comment: "Find configuration stop")) {
                    controller.stop(appState: appState)
                }
                .buttonStyle(VermutButtonStyle(kind: .destructiveOutline))
            } else if controller.phase == .idle || controller.phase == .finished {
                Button(String(localized: "Start", comment: "Find configuration start")) {
                    controller.prepare(
                        game: game,
                        appState: appState,
                        d3dMetalInstalled: appState.hasD3DMetal
                    )
                    controller.start(appState: appState)
                }
                .buttonStyle(VermutButtonStyle(kind: .primary))
                .disabled(controller.total == 0 && controller.phase == .idle)
            }

            if controller.phase == .finished {
                Button(String(localized: "Open logs", comment: "Find configuration open logs")) {
                    controller.openLogs(appState: appState)
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
            }

            Spacer()

            Button(String(localized: "Close", comment: "Find configuration close")) {
                if controller.phase == .running {
                    controller.stop(appState: appState)
                }
                dismiss()
            }
            .buttonStyle(VermutButtonStyle(kind: .ghost))
        }
    }

    private func statusGlyph(_ outcome: FindConfigurationAttemptOutcome) -> String {
        switch outcome {
        case .pending: return "…"
        case .skipped: return "–"
        case .failed: return "✗"
        case .candidate: return "?"
        case .confirmed: return "✓"
        case .rejectedByUser: return "✗"
        case .stopped: return "■"
        }
    }

    private func statusColor(_ outcome: FindConfigurationAttemptOutcome) -> Color {
        switch outcome {
        case .confirmed: return Color.Vermut.green
        case .failed, .rejectedByUser: return Color.Vermut.destructive
        case .candidate: return Color.Vermut.amber
        default: return Color.Vermut.mutedForeground
        }
    }
}
