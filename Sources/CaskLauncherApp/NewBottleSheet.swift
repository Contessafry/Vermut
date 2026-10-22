import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CaskLauncherCore

struct NewBottleSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var engineSelection: String = SettingInheritance.automatic
    @State private var graphicsSelection: String = SettingInheritance.automatic
    @State private var dxmtSelection: String = SettingInheritance.automatic
    @State private var windowsVersion: String = BottleWindowsVersion.win10.rawValue
    @FocusState private var nameFocused: Bool

    @State private var isCreating = false
    @State private var createProgress: Double = 0
    @State private var createStatus: String = ""
    @State private var createError: String?
    @State private var showStopConfirm = false
    @State private var createTask: Task<Void, Never>?
    @State private var winebootPhase = false
    /// Shown after the user tries to pick a disabled backend (picker tags stay selectable on macOS).
    @State private var forcedDXVKHint = false
    @State private var forcedD3DHint = false

    @StateObject private var enginesModel = WineEnginesViewModel()
    @StateObject private var d3dMetalModel = D3DMetalViewModel()

    private var existingNames: [String] {
        appState.customBottles.map(\.name)
    }

    private var nameFailure: BottleNameValidator.Failure? {
        BottleNameValidator.validate(name, existingNames: existingNames)
    }

    /// Binding that rejects DXVK/D3DMetal when unavailable so they cannot stick as the selection.
    private var graphicsSelectionBinding: Binding<String> {
        Binding(
            get: { graphicsSelection },
            set: { newValue in
                if newValue == GraphicsBackend.dxvk.rawValue, !graphicsEnabled(.dxvk) {
                    forcedDXVKHint = true
                    return
                }
                if newValue == GraphicsBackend.d3dmetal.rawValue, !graphicsEnabled(.d3dmetal) {
                    forcedD3DHint = true
                    return
                }
                forcedDXVKHint = false
                forcedD3DHint = false
                graphicsSelection = newValue
            }
        )
    }

    private var draftConfig: BottleConfiguration {
        BottleConfiguration(
            engine: engineSelection,
            graphicsBackend: graphicsSelection == SettingInheritance.automatic
                ? SettingInheritance.automatic
                : (GraphicsBackend(rawValue: graphicsSelection)?.rawValue ?? graphicsSelection),
            dxmtVersion: dxmtSelection,
            windowsVersion: windowsVersion
        )
    }

    private var resolvedEngine: WineEngine {
        WineManager.shared.resolvedCustomEngine(draftConfig)
    }

    private var resolvedGraphics: GraphicsBackend {
        WineManager.shared.resolvedCustomGraphics(draftConfig)
    }

    private var missingEngines: [WineEngine] {
        var missing: [WineEngine] = []
        if !EngineManager.shared.isEngineInstalled(resolvedEngine) {
            missing.append(resolvedEngine)
        }
        return missing
    }

    private var canCreate: Bool {
        guard !isCreating, hasEnoughDiskSpace else { return false }
        // Explicit length check so Create stays off while the name is too long
        // (even if a future validator change forgets `.tooLong`).
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > BottleNameValidator.maxLength { return false }
        return nameFailure == nil
    }

    /// Hint rows only when DXVK / D3DMetal is selected or was just rejected — never for Automatic/DXMT.
    private var showDXVKHelper: Bool {
        graphicsSelection == GraphicsBackend.dxvk.rawValue || forcedDXVKHint
    }

    private var showD3DHelper: Bool {
        graphicsSelection == GraphicsBackend.d3dmetal.rawValue || forcedD3DHint
    }

    private var hasEnoughDiskSpace: Bool {
        let needed = WineManager.requiredFreeBytesForCreation(missingEngines: missingEngines)
        guard let free = WineManager.availableFreeBytes() else { return true }
        return free >= needed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: VermutSpace.s1) {
                        TextField(
                            String(localized: "Name", comment: "New bottle name field"),
                            text: $name
                        )
                        .focused($nameFocused)
                        .disabled(isCreating)
                        .overlay(
                            RoundedRectangle(cornerRadius: VermutRadius.sm, style: .continuous)
                                .strokeBorder(
                                    nameFailure != nil ? Color.Vermut.destructive : Color.clear,
                                    lineWidth: nameFailure != nil ? 1.5 : 0
                                )
                        )
                        .accessibilityHint(
                            nameFailure.map { BottleNameValidator.errorMessage(for: $0) } ?? ""
                        )
                        if let failure = nameFailure {
                            Text(BottleNameValidator.errorMessage(for: failure))
                                .font(VermutType.captionRegular)
                                .foregroundStyle(Color.Vermut.destructive)
                        }
                    }

                    Picker(
                        String(localized: "Wine engine", comment: "New bottle field"),
                        selection: $engineSelection
                    ) {
                        Text(automaticEngineLabel).tag(SettingInheritance.automatic)
                        ForEach(WineEngine.allCases) { engine in
                            Text(enginePickerLabel(engine)).tag(engine.rawValue)
                        }
                    }
                    .disabled(isCreating)

                    Picker(
                        String(localized: "Graphics backend", comment: "New bottle field"),
                        selection: graphicsSelectionBinding
                    ) {
                        Text(automaticGraphicsLabel).tag(SettingInheritance.automatic)
                        ForEach(GraphicsBackend.allCases) { backend in
                            graphicsMenuRow(backend)
                        }
                    }
                    .disabled(isCreating)
                    .onChange(of: engineSelection) { _, _ in
                        // Staging may become available; clear a stale forced hint when DXVK is now OK.
                        if graphicsEnabled(.dxvk) { forcedDXVKHint = false }
                        if graphicsSelection == GraphicsBackend.dxvk.rawValue, !graphicsEnabled(.dxvk) {
                            graphicsSelection = SettingInheritance.automatic
                            forcedDXVKHint = true
                        }
                        if graphicsSelection == GraphicsBackend.d3dmetal.rawValue, !graphicsEnabled(.d3dmetal) {
                            graphicsSelection = SettingInheritance.automatic
                            forcedD3DHint = true
                        }
                    }

                    NewBottleGraphicsHelpers(
                        engineSelection: $engineSelection,
                        graphicsSelection: $graphicsSelection,
                        d3dPresence: d3dMetalModel.presence,
                        showDXVKHelper: showDXVKHelper,
                        showD3DHelper: showD3DHelper,
                        openGuide: {
                            appState.settingsTab = .components
                            appState.section = .settings
                            dismiss()
                        }
                    )

                    if resolvedGraphics == .dxmt {
                        Picker(
                            String(localized: "DXMT version", comment: "New bottle field"),
                            selection: $dxmtSelection
                        ) {
                            Text(automaticDXMTLabel).tag(SettingInheritance.automatic)
                            ForEach(DXMTVersionManager.shared.installedVersions(), id: \.self) { tag in
                                Text(tag).tag(tag)
                            }
                        }
                        .disabled(isCreating)
                    }

                    Picker(
                        String(localized: "Windows version", comment: "New bottle field"),
                        selection: $windowsVersion
                    ) {
                        ForEach(BottleWindowsVersion.allCases) { version in
                            Text(version.displayName).tag(version.rawValue)
                        }
                    }
                    .disabled(isCreating)
                } header: {
                    Text(String(localized: "New Bottle", comment: "Sheet title"))
                } footer: {
                    Text(
                        String(
                            localized: "A separate Windows environment for apps and games outside Steam and Epic.",
                            comment: "New bottle sheet subtitle"
                        )
                    )
                }

                if let note = componentNote {
                    Section {
                        HStack(alignment: .top, spacing: VermutSpace.s2) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(Color.Vermut.info)
                            Text(note)
                                .font(VermutType.body)
                                .foregroundStyle(Color.Vermut.infoSubtleForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, VermutSpace.s1)
                    }
                }

                if !hasEnoughDiskSpace {
                    Section {
                        Text(diskSpaceMessage)
                            .font(VermutType.body)
                            .foregroundStyle(Color.Vermut.errorSubtleForeground)
                    }
                }

                if isCreating {
                    Section {
                        VStack(alignment: .leading, spacing: VermutSpace.s2) {
                            Text(createStatus)
                                .font(VermutType.body)
                            ProgressView(value: createProgress)
                                .accessibilityValue("\(Int(createProgress * 100)) percent")
                        }
                    }
                }

                if let createError {
                    Section {
                        VStack(alignment: .leading, spacing: VermutSpace.s2) {
                            Text(createError)
                                .font(VermutType.body)
                                .foregroundStyle(Color.Vermut.errorSubtleForeground)
                            Button(String(localized: "Try Again", comment: "Retry bottle create")) {
                                startCreate()
                            }
                            .buttonStyle(VermutButtonStyle(kind: .outline))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 520, idealWidth: 520)

            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Dismiss new bottle")) {
                    requestCancel()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(winebootPhase)
                .help(winebootPhase
                      ? String(localized: "Almost done…", comment: "Cancel disabled during wineboot")
                      : "")

                Button(String(localized: "Create Bottle", comment: "Confirm new bottle")) {
                    startCreate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.45)
                .buttonStyle(VermutButtonStyle(kind: .primary))
                .accessibilityHint(
                    nameFailure.map { BottleNameValidator.errorMessage(for: $0) }
                        ?? ""
                )
            }
            .padding(VermutSpace.s4)
        }
        .onAppear {
            name = BottleNameValidator.suggestedName(existingNames: existingNames)
            enginesModel.refresh()
            d3dMetalModel.rescan()
            DispatchQueue.main.async { nameFocused = true }
        }
        .confirmationDialog(
            String(localized: "Stop creating “\(name.trimmingCharacters(in: .whitespacesAndNewlines))”?", comment: "Cancel create title"),
            isPresented: $showStopConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Stop", comment: "Stop creating bottle"), role: .destructive) {
                createTask?.cancel()
                createTask = nil
                isCreating = false
                winebootPhase = false
                dismiss()
            }
            Button(String(localized: "Keep Going", comment: "Continue creating bottle"), role: .cancel) {}
        } message: {
            Text(
                String(
                    localized: "The download will stop. Nothing will be created.",
                    comment: "Cancel create message"
                )
            )
        }
    }

    @ViewBuilder
    private func graphicsMenuRow(_ backend: GraphicsBackend) -> some View {
        let enabled = graphicsEnabled(backend)
        // Keep a tag so the option appears in the menu; `graphicsSelectionBinding`
        // rejects unavailable backends so they never become the committed selection.
        Text(enabled ? backend.shortLabel : disabledGraphicsLabel(backend))
            .tag(backend.rawValue)
            .disabled(!enabled)
            .foregroundStyle(enabled ? Color.primary : Color.secondary)
            .accessibilityLabel(
                enabled
                ? backend.shortLabel
                : "\(backend.shortLabel), unavailable, \(disabledGraphicsLabel(backend))"
            )
    }

    private func graphicsEnabled(_ backend: GraphicsBackend) -> Bool {
        switch backend {
        case .dxvk:
            // Do not use resolvedEngine here: DXVK→Staging policy would make DXVK look enabled.
            let selected: WineEngine
            if SettingInheritance.isAutomatic(engineSelection) {
                selected = WineEngine.resolved(from: appState.configuration.defaultEngine)
            } else {
                selected = WineEngine(rawValue: engineSelection) ?? .defaultEngine
            }
            return selected == .staging
        case .d3dmetal:
            return d3dMetalModel.presence.isUsable
        default:
            return true
        }
    }

    private func disabledGraphicsLabel(_ backend: GraphicsBackend) -> String {
        switch backend {
        case .dxvk:
            return "\(backend.shortLabel) — Requires Wine Staging."
        case .d3dmetal:
            return "\(backend.shortLabel) — \(d3dMetalDisabledReason)"
        default:
            return backend.shortLabel
        }
    }

    private var d3dMetalDisabledReason: String {
        switch d3dMetalModel.presence {
        case .notFound:
            return String(localized: "Game Porting Toolkit not found.", comment: "D3DMetal disabled")
        case .unsupported:
            return String(localized: "Unsupported version. Update the Game Porting Toolkit.", comment: "D3DMetal disabled")
        case .invalid:
            return String(localized: "The saved D3DMetal location isn’t valid.", comment: "D3DMetal disabled")
        case .unavailableOnIntel:
            return String(localized: "Requires a Mac with Apple silicon.", comment: "D3DMetal disabled")
        case .found:
            return ""
        }
    }

    private var automaticEngineLabel: String {
        let name = WineEngine.resolved(from: appState.configuration.defaultEngine).userFacingName
        return "Automatic (\(name))"
    }

    private var automaticGraphicsLabel: String {
        let backend = GraphicsBackend(rawValue: appState.configuration.defaultGraphicsBackend) ?? .dxmt
        return "Automatic (\(backend.shortLabel))"
    }

    private var automaticDXMTLabel: String {
        let tag = appState.configuration.defaultDXMTVersion
        return "Automatic (\(tag))"
    }

    private func enginePickerLabel(_ engine: WineEngine) -> String {
        let status = WineEnginesViewModel.pickerStatusLabel(for: engine)
        if !EngineManager.shared.isEngineInstalled(engine) {
            return "\(engine.userFacingName) · Not installed"
        }
        return "\(engine.userFacingName) · \(status)"
    }

    private var componentNote: String? {
        guard let engine = missingEngines.first else { return nil }
        let bytes = WineEnginesViewModel.approximateDownloadBytes[engine]
        let size = bytes.map { WineEnginesViewModel.formatBytes($0) } ?? "several hundred MB"
        return String(
            localized: "\(engine.userFacingName) isn’t installed. Vermut will download it (about \(size)) when you create the bottle.",
            comment: "Missing engine download note"
        )
    }

    private var diskSpaceMessage: String {
        let needed = WineManager.requiredFreeBytesForCreation(missingEngines: missingEngines)
        let label = WineEnginesViewModel.formatBytes(needed)
        return String(
            localized: "Not enough disk space. About \(label) is needed.",
            comment: "Disk full before create"
        )
    }

    private func requestCancel() {
        if isCreating && !winebootPhase {
            showStopConfirm = true
        } else if !isCreating {
            dismiss()
        }
    }

    private func startCreate() {
        guard canCreate else { return }
        createError = nil
        isCreating = true
        createProgress = 0
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = draftConfig
        let id = UUID()

        createTask = Task {
            do {
                for engine in missingEngines {
                    try Task.checkCancellation()
                    await MainActor.run {
                        createStatus = String(
                            localized: "Downloading \(engine.userFacingName)…",
                            comment: "Create bottle download status"
                        )
                    }
                    try await EngineManager.shared.downloadEngine(engine) { progress in
                        Task { @MainActor in
                            createProgress = progress * 0.7
                            createStatus = String(
                                localized: "Downloading \(engine.userFacingName)… \(Int(progress * 100))%",
                                comment: "Create bottle download percent"
                            )
                        }
                    }
                }

                try Task.checkCancellation()
                await MainActor.run {
                    winebootPhase = true
                    createProgress = 0.75
                    createStatus = String(localized: "Creating bottle…", comment: "wineboot status")
                }

                try await WineManager.shared.createCustomPrefix(id: id, config: config)
                let bottle = CustomBottle(id: id, name: trimmed, configuration: config)
                try await MainActor.run {
                    try appState.registerCustomBottle(bottle)
                    isCreating = false
                    winebootPhase = false
                    appState.section = .customBottle(id)
                    dismiss()
                }
            } catch is CancellationError {
                await MainActor.run {
                    isCreating = false
                    winebootPhase = false
                    try? WineManager.shared.deleteCustomBottle(id: id)
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    winebootPhase = false
                    try? WineManager.shared.deleteCustomBottle(id: id)
                    createError = String(
                        localized: "Couldn’t create the bottle. Nothing was left behind.",
                        comment: "Create bottle failed"
                    )
                }
            }
        }
    }
}

/// Extra actions shown when DXVK / D3DMetal need a fix (picker menus can't host buttons).
struct NewBottleGraphicsHelpers: View {
    @Binding var engineSelection: String
    @Binding var graphicsSelection: String
    let d3dPresence: D3DMetalPresence
    var showDXVKHelper: Bool
    var showD3DHelper: Bool
    var openGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            if showDXVKHelper, engineSelection != WineEngine.staging.rawValue {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Requires Wine Staging.", comment: "DXVK helper"))
                            .font(VermutType.captionRegular)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                        Text(
                            String(
                                localized: "Wine Staging is required for DXVK (Vermut Wine has no Vulkan loader).",
                                comment: "DXVK Staging extended help"
                            )
                        )
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                    }
                    Spacer()
                    Button(String(localized: "Switch to Staging", comment: "Enable DXVK")) {
                        engineSelection = WineEngine.staging.rawValue
                        graphicsSelection = GraphicsBackend.dxvk.rawValue
                    }
                    .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall))
                    .accessibilityLabel(
                        String(
                            localized: "DXVK, unavailable, requires Wine Staging",
                            comment: "a11y DXVK disabled"
                        )
                    )
                }
            }
            if showD3DHelper {
                HStack {
                    Text(d3dReason)
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                    Spacer()
                    Button(String(localized: "Open the guide", comment: "D3DMetal guide")) {
                        openGuide()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var d3dReason: String {
        switch d3dPresence {
        case .notFound: return String(localized: "Game Porting Toolkit not found.", comment: "")
        case .unsupported: return String(localized: "Unsupported version. Update the Game Porting Toolkit.", comment: "")
        case .invalid: return String(localized: "The saved D3DMetal location isn’t valid.", comment: "")
        case .unavailableOnIntel: return String(localized: "Requires a Mac with Apple silicon.", comment: "")
        case .found: return ""
        }
    }
}
