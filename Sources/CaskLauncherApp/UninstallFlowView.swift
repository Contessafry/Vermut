import SwiftUI
import AppKit
import CaskLauncherCore

/// Sendable cancel flag for the background trash worker.
private final class UninstallCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }

    func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
    }
}

/// Multi-step Uninstall Vermut sheet (selection → processes → confirm → progress → done).
struct UninstallFlowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var plan: UninstallPlan?
    @State private var isCalculating = true
    @State private var step: Step = .selection
    @State private var running: [UninstallRunningProcess] = []
    @State private var confirmText = ""
    @State private var showSystemConfirm = false
    @State private var showForceQuitConfirm = false
    @State private var forceQuitPIDs: [pid_t] = []
    @State private var progressLabel = ""
    @State private var progressIndex = 0
    @State private var progressTotal = 0
    @State private var cancelRequested = false
    @State private var cancelFlag: UninstallCancelFlag?
    @State private var summary: UninstallRunSummary?
    @State private var bottlesExpanded = false

    /// Sendable cancel flag for the background trash worker.
    private final class UninstallCancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var _cancelled = false
        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return _cancelled
        }
        func cancel() {
            lock.lock(); _cancelled = true; lock.unlock()
        }
    }

    private enum Step: Equatable {
        case selection
        case processes
        case bottleConfirm
        case progress
        case done
    }

    var body: some View {
        Group {
            switch step {
            case .selection:
                selectionStep
            case .processes:
                processesStep
            case .bottleConfirm:
                bottleConfirmStep
            case .progress:
                progressStep
            case .done:
                doneStep
            }
        }
        .frame(width: 520)
        .frame(minHeight: 420, maxHeight: 640)
        .background(Color.Vermut.popover)
        .task { await loadPlan() }
        .alert(
            String(localized: "Remove %@ from your Mac?", comment: "Uninstall confirm title")
                .replacingOccurrences(
                    of: "%@",
                    with: UninstallSizeCalculator.formattedByteCount(plan?.selectedByteCount ?? 0)
                ),
            isPresented: $showSystemConfirm
        ) {
            Button(String(localized: "Cancel", comment: "Uninstall alert cancel"), role: .cancel) {}
            Button(String(localized: "Remove", comment: "Uninstall alert remove"), role: .destructive) {
                beginRemovalAfterConfirm()
            }
        } message: {
            Text(String(
                localized: "Items go to the Trash. Vermut will quit when it's done.",
                comment: "Uninstall confirm body"
            ))
        }
        .alert(
            String(localized: "Force Quit", comment: "Force quit alert title"),
            isPresented: $showForceQuitConfirm
        ) {
            Button(String(localized: "Cancel", comment: "Force quit cancel"), role: .cancel) {}
            Button(String(localized: "Force Quit", comment: "Force quit confirm"), role: .destructive) {
                performForceQuit()
            }
        } message: {
            Text(String(
                localized: "Unsaved progress in these programs will be lost.",
                comment: "Force quit warning"
            ))
        }
    }

    // MARK: - Selection (mockup 1)

    private var selectionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: VermutSpace.s2) {
                Text(String(localized: "Uninstall Vermut", comment: "Uninstall sheet title"))
                    .font(VermutType.title)
                    .foregroundStyle(Color.Vermut.foreground)
                Text(String(
                    localized: "Choose what to remove. Native Steam, Epic and GOG apps on your Mac are never touched.",
                    comment: "Uninstall sheet subtitle"
                ))
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(VermutSpace.s6)
            .padding(.bottom, VermutSpace.s2)

            ScrollView {
                VStack(alignment: .leading, spacing: VermutSpace.s1) {
                    if let plan {
                        selectionRow(
                            title: plan.app.displayName,
                            detail: plan.app.detail,
                            bytes: plan.app.byteCount,
                            selected: plan.app.isSelected
                        ) {
                            self.plan?.app.isSelected.toggle()
                        }

                        bottlesGroup(plan)

                        selectionRow(
                            title: plan.engines.displayName,
                            detail: plan.engines.detail,
                            bytes: plan.engines.byteCount,
                            selected: plan.engines.isSelected
                        ) {
                            self.plan?.engines.isSelected.toggle()
                        }
                        selectionRow(
                            title: plan.caches.displayName,
                            detail: plan.caches.detail,
                            bytes: plan.caches.byteCount,
                            selected: plan.caches.isSelected
                        ) {
                            self.plan?.caches.isSelected.toggle()
                        }
                        selectionRow(
                            title: plan.logs.displayName,
                            detail: plan.logs.detail,
                            bytes: plan.logs.byteCount,
                            selected: plan.logs.isSelected
                        ) {
                            self.plan?.logs.isSelected.toggle()
                        }
                        selectionRow(
                            title: plan.preferences.displayName,
                            detail: plan.preferences.detail,
                            bytes: plan.preferences.byteCount,
                            selected: plan.preferences.isSelected
                        ) {
                            self.plan?.preferences.isSelected.toggle()
                        }
                    } else {
                        HStack(spacing: VermutSpace.s2) {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "Calculating…", comment: "Uninstall size calculating"))
                                .font(VermutType.body)
                                .foregroundStyle(Color.Vermut.mutedForeground)
                        }
                        .padding(.horizontal, VermutSpace.s6)
                    }
                }
                .padding(.bottom, VermutSpace.s4)
            }

            Divider()
            HStack {
                Button(
                    (plan?.isEverythingSelected == true)
                        ? String(localized: "Deselect All", comment: "Uninstall deselect all")
                        : String(localized: "Select All", comment: "Uninstall select all")
                ) {
                    guard var p = plan else { return }
                    if p.isEverythingSelected {
                        p.deselectAll()
                    } else {
                        p.selectAll()
                    }
                    plan = p
                }
                .buttonStyle(.plain)
                .font(VermutType.bodyEmphasis)
                .foregroundStyle(Color.Vermut.foreground)
                .disabled(plan == nil)

                Spacer()

                Button(String(localized: "Cancel", comment: "Uninstall cancel")) {
                    dismiss()
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
                .keyboardShortcut(.cancelAction)

                Button(primaryRemoveTitle) {
                    onPrimaryRemove()
                }
                .buttonStyle(VermutButtonStyle(kind: .primary))
                .disabled(plan?.isNothingSelected != false)
                .keyboardShortcut(.defaultAction)
            }
            .padding(VermutSpace.s6)
        }
    }

    private func bottlesGroup(_ plan: UninstallPlan) -> some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            HStack(alignment: .top, spacing: VermutSpace.s3) {
                bottlesParentCheckbox(plan)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(String(localized: "Bottles", comment: "Uninstall bottles group"))
                            .font(VermutType.bodyEmphasis)
                        Spacer()
                        sizeLabel(plan.bottles.reduce(0) { $0 + $1.byteCount })
                    }
                    Text(bottlesSubtitle(plan))
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                }
                Button {
                    bottlesExpanded.toggle()
                } label: {
                    Image(systemName: bottlesExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bottlesExpanded ? "Collapse bottles" : "Expand bottles")
            }
            .padding(.horizontal, VermutSpace.s6)
            .padding(.vertical, VermutSpace.s2)
            .contentShape(Rectangle())
            .onTapGesture { bottlesExpanded.toggle() }

            if bottlesExpanded {
                ForEach(plan.bottles, id: \.id) { bottle in
                    selectionRow(
                        title: bottle.displayName,
                        detail: bottle.detail,
                        bytes: bottle.byteCount,
                        selected: bottle.isSelected,
                        indented: true
                    ) {
                        if let id = bottle.bottleID {
                            self.plan?.setBottleSelected(id: id, selected: !bottle.isSelected)
                            refreshLogs()
                        }
                    }
                }
            }

            if plan.hasSelectedBottle {
                bottleWarning
                    .padding(.horizontal, VermutSpace.s6)
                    .padding(.top, VermutSpace.s1)
            }
        }
    }

    private func bottlesParentCheckbox(_ plan: UninstallPlan) -> some View {
        Button {
            var p = plan
            switch p.bottlesTriState {
            case .off, .mixed:
                p.setAllBottlesSelected(true)
            case .on:
                p.setAllBottlesSelected(false)
            }
            self.plan = p
            refreshLogs()
        } label: {
            Image(systemName: bottlesCheckboxSymbol(plan.bottlesTriState))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.Vermut.foreground)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Bottles", comment: "Uninstall bottles a11y"))
        .accessibilityValue(bottlesA11yValue(plan.bottlesTriState))
    }

    private var bottleWarning: some View {
        HStack(alignment: .top, spacing: VermutSpace.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.Vermut.warning)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: VermutSpace.s1) {
                Text(String(
                    localized: "Bottles contain installed games and local saves. Games that don't sync saves to the cloud will lose progress.",
                    comment: "Bottle loss warning"
                ))
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.warningSubtleForeground)
                .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Show in Finder", comment: "Reveal bottles")) {
                    NSWorkspace.shared.activateFileViewerSelecting([PathManager.shared.bottlesURL])
                }
                .buttonStyle(.plain)
                .font(VermutType.caption)
                .foregroundStyle(Color.Vermut.foreground)
                .underline()
            }
        }
        .padding(VermutSpace.s3)
        .background(Color.Vermut.warningSubtle)
        .overlay(
            RoundedRectangle(cornerRadius: VermutRadius.sm, style: .continuous)
                .strokeBorder(Color.Vermut.warningBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: VermutRadius.sm, style: .continuous))
        .accessibilityAddTraits(.isStaticText)
    }

    private func selectionRow(
        title: String,
        detail: String,
        bytes: Int64,
        selected: Bool,
        indented: Bool = false,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: VermutSpace.s3) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.Vermut.foreground)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(title)
                                .font(VermutType.bodyEmphasis)
                                .foregroundStyle(Color.Vermut.foreground)
                            Spacer(minLength: VermutSpace.s2)
                            sizeLabel(bytes)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(VermutType.bodyEmphasis)
                            sizeLabel(bytes)
                        }
                    }
                    if !detail.isEmpty {
                        Text(detail)
                            .font(VermutType.captionRegular)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.leading, indented ? VermutSpace.s8 : VermutSpace.s6)
            .padding(.trailing, VermutSpace.s6)
            .padding(.vertical, VermutSpace.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(UninstallSizeCalculator.formattedByteCount(bytes))")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func sizeLabel(_ bytes: Int64) -> some View {
        Group {
            if isCalculating && bytes == 0 {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(String(localized: "Calculating…", comment: "Size calculating short"))
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                }
            } else {
                Text(UninstallSizeCalculator.formattedByteCount(bytes))
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .monospacedDigit()
            }
        }
    }

    private var primaryRemoveTitle: String {
        guard let plan else {
            return String(localized: "Remove…", comment: "Uninstall primary placeholder")
        }
        if plan.isNothingSelected {
            return String(localized: "Remove", comment: "Uninstall primary empty")
        }
        let onlyApp = plan.app.isSelected
            && !plan.hasSelectedBottle
            && !plan.engines.isSelected
            && !plan.caches.isSelected
            && !plan.logs.isSelected
            && !plan.preferences.isSelected
        if onlyApp {
            return String(localized: "Remove Vermut", comment: "Uninstall primary app only")
        }
        let size = UninstallSizeCalculator.formattedByteCount(plan.selectedByteCount)
        return String(localized: "Remove \(size)", comment: "Uninstall primary with size")
    }

    // MARK: - Processes (mockup 2)

    private var processesStep: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s4) {
            VStack(alignment: .leading, spacing: VermutSpace.s2) {
                Text(String(localized: "Uninstall Vermut", comment: "Uninstall sheet title"))
                    .font(VermutType.title)
                Text(String(localized: "Quit running programs first", comment: "Quit processes title"))
                    .font(VermutType.headline)
                Text(String(
                    localized: "These programs are running in Vermut bottles. Vermut will ask them to quit. Nothing is closed until you continue.",
                    comment: "Quit processes subtitle"
                ))
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(running) { proc in
                    HStack(alignment: .center, spacing: VermutSpace.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proc.name)
                                .font(VermutType.bodyEmphasis)
                            Text(proc.detail)
                                .font(VermutType.captionRegular)
                                .foregroundStyle(Color.Vermut.mutedForeground)
                        }
                        Spacer()
                        processStatus(proc)
                    }
                    .padding(.horizontal, VermutSpace.s3)
                    .padding(.vertical, VermutSpace.s3)
                    if proc.id != running.last?.id {
                        Divider()
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous)
                    .strokeBorder(Color.Vermut.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))

            HStack(alignment: .top, spacing: VermutSpace.s2) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.Vermut.info)
                Text(String(
                    localized: "Steam and GOG installed natively on macOS aren't affected.",
                    comment: "Native stores info"
                ))
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.infoSubtleForeground)
            }
            .padding(VermutSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.Vermut.infoSubtle)
            .overlay(
                RoundedRectangle(cornerRadius: VermutRadius.sm, style: .continuous)
                    .strokeBorder(Color.Vermut.infoBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.sm, style: .continuous))

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Uninstall cancel")) {
                    dismiss()
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Quit and Continue", comment: "Quit and continue")) {
                    Task { await quitAndContinue() }
                }
                .buttonStyle(VermutButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(VermutSpace.s6)
    }

    @ViewBuilder
    private func processStatus(_ proc: UninstallRunningProcess) -> some View {
        switch proc.status {
        case .running:
            Text(String(localized: "Running", comment: "Process running badge"))
                .font(VermutType.caption)
                .padding(.horizontal, VermutSpace.s2)
                .padding(.vertical, 2)
                .background(Color.Vermut.successSubtle)
                .foregroundStyle(Color.Vermut.successSubtleForeground)
                .clipShape(Capsule())
        case .willCancel:
            Text(String(localized: "Will cancel", comment: "Download will cancel"))
                .font(VermutType.caption)
                .padding(.horizontal, VermutSpace.s2)
                .padding(.vertical, 2)
                .background(Color.Vermut.muted)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .clipShape(Capsule())
        case .didNotQuit:
            HStack(spacing: VermutSpace.s2) {
                Text(String(localized: "Didn't quit", comment: "Process didn't quit"))
                    .font(VermutType.caption)
                    .foregroundStyle(Color.Vermut.warningForeground)
                Button(String(localized: "Force Quit…", comment: "Force quit button")) {
                    forceQuitPIDs = [proc.pid]
                    showForceQuitConfirm = true
                }
                .buttonStyle(VermutButtonStyle(
                    kind: .outline,
                    height: VermutHeight.buttonSmall,
                    radius: VermutRadius.xsPlus,
                    font: VermutType.callout,
                    horizontalPadding: VermutSpace.s2
                ))
            }
        }
    }

    // MARK: - Bottle type-to-confirm

    private var bottleConfirmStep: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s4) {
            Text(String(localized: "Uninstall Vermut", comment: "Uninstall sheet title"))
                .font(VermutType.title)
            Text(String(localized: "Confirm (bottles selected)", comment: "Bottle confirm heading"))
                .font(VermutType.headline)
            Text(
                String(localized: "Remove %@ from your Mac?", comment: "Uninstall confirm title")
                    .replacingOccurrences(
                        of: "%@",
                        with: UninstallSizeCalculator.formattedByteCount(plan?.selectedByteCount ?? 0)
                    )
            )
            .font(VermutType.bodyEmphasis)
            Text(bottleConfirmSubtitle)
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                String(localized: "delete", comment: "Type-to-confirm placeholder"),
                text: $confirmText
            )
            .textFieldStyle(.roundedBorder)
            .font(VermutType.body)

            Text(String(localized: "Type “delete” to confirm", comment: "Type delete hint"))
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.mutedForeground)

            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Confirm cancel")) {
                    step = .selection
                    confirmText = ""
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
                .keyboardShortcut(.defaultAction)

                Button(String(localized: "Remove", comment: "Confirm remove")) {
                    beginRemovalAfterConfirm()
                }
                .buttonStyle(VermutButtonStyle(kind: .primary))
                .disabled(confirmText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "delete")
            }
        }
        .padding(VermutSpace.s6)
    }

    private var bottleConfirmSubtitle: String {
        let count = plan?.selectedBottleCount ?? 0
        let base = String(
            localized: "Items go to the Trash. Vermut will quit when it's done.",
            comment: "Uninstall confirm body"
        )
        if count == 1 {
            return base + " " + String(
                localized: "1 bottle with local saves is included.",
                comment: "One bottle in confirm"
            )
        }
        if count > 1 {
            return base + " " + String(
                localized: "\(count) bottles with local saves are included.",
                comment: "Many bottles in confirm"
            )
        }
        return base
    }

    // MARK: - Progress / Done

    private var progressStep: some View {
        VStack(spacing: VermutSpace.s4) {
            ProgressView()
                .controlSize(.regular)
            Text(progressLabel.isEmpty
                ? String(localized: "Removing…", comment: "Removing progress")
                : progressLabel)
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .accessibilityLabel(progressAccessibility)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Cancel mid-uninstall")) {
                    cancelRequested = true
                    cancelFlag?.cancel()
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
                .disabled(cancelRequested)
            }
        }
        .padding(VermutSpace.s6)
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var progressAccessibility: String {
        if progressTotal > 0 {
            return "\(progressLabel), \(progressIndex) of \(progressTotal)"
        }
        return progressLabel
    }

    private var doneStep: some View {
        Group {
            if let summary, summary.hasFailures {
                failureDone(summary)
            } else {
                successDone(summary)
            }
        }
    }

    private func successDone(_ summary: UninstallRunSummary?) -> some View {
        VStack(alignment: .leading, spacing: VermutSpace.s4) {
            HStack(spacing: VermutSpace.s2) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.Vermut.success)
                    .font(.system(size: 22))
                Text(String(localized: "Vermut removed", comment: "Uninstall success title"))
                    .font(VermutType.title)
            }
            Text(
                String(localized: "%@ moved to the Trash", comment: "Bytes moved to trash")
                    .replacingOccurrences(
                        of: "%@",
                        with: UninstallSizeCalculator.formattedByteCount(summary?.removedByteCount ?? 0)
                    )
                + ". "
                + String(
                    localized: "Empty the Trash to free up the space.",
                    comment: "Empty trash hint"
                )
            )
            .font(VermutType.body)
            .foregroundStyle(Color.Vermut.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(summary?.successResults ?? []) { item in
                    HStack {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.Vermut.success)
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.displayName)
                            .font(VermutType.body)
                        if let note = item.message, item.outcome == .deferredApp {
                            Text("· \(note)")
                                .font(VermutType.captionRegular)
                                .foregroundStyle(Color.Vermut.mutedForeground)
                        }
                        Spacer()
                        Text(UninstallSizeCalculator.formattedByteCount(item.byteCount))
                            .font(VermutType.captionRegular)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                    }
                    .padding(.vertical, VermutSpace.s2)
                }
            }
            .padding(VermutSpace.s3)
            .overlay(
                RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous)
                    .strokeBorder(Color.Vermut.border, lineWidth: 1)
            )

            if let summary, summary.keptBottleCount > 0, let path = summary.keptBottlesPath {
                HStack(alignment: .top, spacing: VermutSpace.s2) {
                    Text(
                        String(
                            localized: "Kept: \(summary.keptBottleCount) bottles (\(UninstallSizeCalculator.formattedByteCount(summary.keptBottleBytes))) in \(path.path)",
                            comment: "Kept bottles summary"
                        )
                    )
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    Button(String(localized: "Show in Finder", comment: "Show kept bottles")) {
                        NSWorkspace.shared.activateFileViewerSelecting([path])
                    }
                    .buttonStyle(.plain)
                    .font(VermutType.caption)
                    .underline()
                }
                .padding(VermutSpace.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous)
                        .strokeBorder(Color.Vermut.border, lineWidth: 1)
                )
            }

            HStack(spacing: VermutSpace.s4) {
                Link(
                    String(localized: "Reinstall Vermut", comment: "Reinstall link"),
                    destination: URL(string: "https://vermut.vercel.app")!
                )
                Link(
                    String(localized: "Tell us why you're leaving", comment: "Feedback link"),
                    destination: URL(string: "https://github.com/Contessafry/Vermut/discussions")!
                )
            }
            .font(VermutType.bodyEmphasis)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(String(localized: "Quit Vermut", comment: "Quit after uninstall")) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(VermutButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(VermutSpace.s6)
    }

    private func failureDone(_ summary: UninstallRunSummary) -> some View {
        VStack(alignment: .leading, spacing: VermutSpace.s4) {
            HStack(spacing: VermutSpace.s2) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(Color.Vermut.destructive)
                    .font(.system(size: 22))
                Text(String(localized: "Some items couldn't be removed", comment: "Partial failure title"))
                    .font(VermutType.title)
            }
            Text(String(
                localized: "Everything else was moved to the Trash.",
                comment: "Partial failure subtitle"
            ))
            .font(VermutType.body)
            .foregroundStyle(Color.Vermut.mutedForeground)

            VStack(alignment: .leading, spacing: VermutSpace.s3) {
                ForEach(summary.failureResults) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.displayName)
                                .font(VermutType.bodyEmphasis)
                            VermutBadge(
                                kind: .error,
                                text: item.outcome == .skipped
                                    ? String(localized: "Skipped", comment: "Skipped badge")
                                    : String(localized: "Failed", comment: "Failed badge")
                            )
                        }
                        if let message = item.message {
                            Text(message)
                                .font(VermutType.captionRegular)
                                .foregroundStyle(Color.Vermut.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(VermutSpace.s3)
            .overlay(
                RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous)
                    .strokeBorder(Color.Vermut.border, lineWidth: 1)
            )

            HStack(spacing: VermutSpace.s2) {
                Button(String(localized: "Show in Finder", comment: "Show failed item")) {
                    if let url = summary.failureResults.first?.revealURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
                Button(String(localized: "Try Again", comment: "Retry uninstall")) {
                    step = .selection
                    summary = nil
                    Task { await loadPlan() }
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(String(localized: "Quit Vermut", comment: "Quit after uninstall")) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(VermutButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(VermutSpace.s6)
    }

    // MARK: - Actions

    private func loadPlan() async {
        isCalculating = true
        let custom = appState.customBottles
        var counts: [GameStore: Int] = [:]
        for store in GameStore.allCases {
            counts[store] = appState.installedGames.filter { $0.store == store && $0.isInstalled }.count
        }
        let built = await Task.detached(priority: .userInitiated) {
            UninstallPlanBuilder.makeDefaultPlan(
                context: UninstallPlanBuilder.Context(
                    customBottles: custom,
                    gameCountByStore: counts
                )
            )
        }.value
        plan = built
        bottlesExpanded = built.bottlesExpanded
        isCalculating = false
    }

    private func refreshLogs() {
        guard var p = plan else { return }
        UninstallPlanBuilder.refreshLogs(
            plan: &p,
            context: UninstallPlanBuilder.Context(customBottles: appState.customBottles)
        )
        plan = p
    }

    private func onPrimaryRemove() {
        guard let plan, !plan.isNothingSelected else { return }
        let processes = collectRunning()
        if !processes.isEmpty {
            running = processes
            step = .processes
            return
        }
        presentConfirm()
    }

    private func collectRunning() -> [UninstallRunningProcess] {
        let prefixes = PrefixProcessTerminator.vermutPrefixPaths()
        var list = UninstallProcessScout.discoverWineProcesses(
            prefixes: prefixes,
            bottleLabelForPrefix: UninstallProcessScout.bottleLabel(forPrefix:)
        )
        var downloads: [UninstallProcessScout.DownloadStub] = []
        for store in GameStore.allCases {
            if let status = appState.storeStatuses[store], status.isInstallInProgress {
                downloads.append(.init(name: "Install: \(store.rawValue)"))
            }
        }
        for download in appState.gameDownloads.values where download.error == nil {
            downloads.append(.init(name: "Download: \(download.name)"))
        }
        list.append(contentsOf: UninstallProcessScout.downloadPlaceholders(downloads))
        return list
    }

    private func presentConfirm() {
        guard let plan else { return }
        if plan.hasSelectedBottle {
            confirmText = ""
            step = .bottleConfirm
        } else {
            showSystemConfirm = true
        }
    }

    private func quitAndContinue() async {
        let prefixes = Set(running.compactMap(\.prefixPath)).sorted()
        // Cancel downloads first (AppState).
        await MainActor.run {
            for store in GameStore.allCases {
                if appState.storeStatuses[store]?.isInstallInProgress == true {
                    appState.cancelInstall(store)
                }
            }
            for download in appState.gameDownloads.values {
                appState.cancelEpicGameDownload(download)
            }
        }
        await Task.detached(priority: .userInitiated) {
            UninstallProcessScout.softQuit(prefixes: Array(prefixes))
        }.value

        // Re-discover leftovers.
        var leftover = UninstallProcessScout.discoverWineProcesses(
            prefixes: PrefixProcessTerminator.vermutPrefixPaths(),
            bottleLabelForPrefix: UninstallProcessScout.bottleLabel(forPrefix:)
        )
        if leftover.isEmpty {
            presentConfirm()
            return
        }
        leftover = leftover.map {
            var copy = $0
            copy.status = .didNotQuit
            return copy
        }
        running = leftover
    }

    private func performForceQuit() {
        let pids = forceQuitPIDs
        forceQuitPIDs = []
        Task.detached(priority: .userInitiated) {
            _ = UninstallProcessScout.forceQuit(pids: pids)
        }
        // Refresh list shortly after.
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let leftover = UninstallProcessScout.discoverWineProcesses(
                prefixes: PrefixProcessTerminator.vermutPrefixPaths(),
                bottleLabelForPrefix: UninstallProcessScout.bottleLabel(forPrefix:)
            )
            if leftover.isEmpty {
                presentConfirm()
            } else {
                running = leftover.map {
                    var copy = $0
                    copy.status = .didNotQuit
                    return copy
                }
            }
        }
    }

    private func beginRemovalAfterConfirm() {
        guard let plan else { return }
        cancelRequested = false
        let cancelFlag = UninstallCancelFlag()
        step = .progress
        progressLabel = String(localized: "Removing…", comment: "Removing progress")
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                UninstallExecutor.run(
                    plan: plan,
                    options: UninstallExecutor.Options(scheduleAppHelper: plan.app.isSelected),
                    progress: { event in
                        Task { @MainActor in
                            switch event {
                            case .started(let name, let index, let total):
                                progressIndex = index
                                progressTotal = total
                                progressLabel = String(
                                    localized: "Removing \(name)…",
                                    comment: "Removing item progress"
                                )
                            case .finished:
                                break
                            }
                        }
                    },
                    isCancelled: { cancelFlag.isCancelled }
                )
            }.value
            summary = result
            step = .done
        }
        // Keep UI flag and sendable flag in sync when the user cancels.
        self.cancelFlag = cancelFlag
    }

    // MARK: - Helpers

    private func bottlesSubtitle(_ plan: UninstallPlan) -> String {
        let selected = plan.selectedBottleCount
        let total = plan.bottles.count
        if total == 0 {
            return String(localized: "No bottles found", comment: "No bottles")
        }
        if selected == 0 {
            return String(
                localized: "None selected · contain installed games and saves",
                comment: "Bottles none selected"
            )
        }
        return String(
            localized: "\(selected) of \(total) selected · contain installed games and saves",
            comment: "Bottles partial selected"
        )
    }

    private func bottlesCheckboxSymbol(_ state: UninstallPlan.TriState) -> String {
        switch state {
        case .off: return "square"
        case .on: return "checkmark.square.fill"
        case .mixed: return "minus.square.fill"
        }
    }

    private func bottlesA11yValue(_ state: UninstallPlan.TriState) -> String {
        switch state {
        case .off: return "Not selected"
        case .on: return "Selected"
        case .mixed: return "Mixed"
        }
    }
}
