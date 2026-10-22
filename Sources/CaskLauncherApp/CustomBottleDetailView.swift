import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CaskLauncherCore

struct CustomBottleDetailView: View {
    let bottleID: UUID
    @EnvironmentObject var appState: AppState

    @State private var bottle: CustomBottle?
    @State private var sizeBytes: Int64 = 0
    @State private var isRunning = false
    @State private var confirmDelete = false
    @State private var showSettings = false
    @State private var showFilePicker = false
    @State private var errorBanner: String?
    @State private var warningBanner: String?

    private var displayName: String { bottle?.name ?? "Bottle" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VermutSpace.s6) {
                header
                if let warningBanner {
                    callout(kind: .warning, text: warningBanner)
                }
                if let errorBanner {
                    callout(kind: .error, text: errorBanner)
                }
                programsSection
            }
            .padding(VermutSpace.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.Vermut.background)
        .onAppear(perform: reload)
        .onChange(of: bottleID) { _, _ in reload() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            refreshRunning()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.exe, .msi]
        ) { result in
            handlePickedExecutable(result)
        }
        .sheet(isPresented: $showSettings) {
            if let bottle {
                BottleSettingsSheet(bottle: bottle) { updated in
                    self.bottle = updated
                    appState.updateCustomBottle(updated)
                }
                .environmentObject(appState)
            }
        }
        .confirmationDialog(
            String(localized: "Delete “\(displayName)”?", comment: "Delete custom bottle title"),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete", comment: "Confirm delete bottle"), role: .destructive) {
                deleteBottle()
            }
            Button(String(localized: "Cancel", comment: "Cancel delete"), role: .cancel) {}
        } message: {
            Text(
                String(
                    localized: "This deletes the bottle and every program installed in it. This can’t be undone.",
                    comment: "Delete custom bottle message"
                )
            )
        }
        .background {
            Group {
                Button("") { showFilePicker = true }
                    .keyboardShortcut("o", modifiers: .command)
                Button("") { showSettings = true }
                    .keyboardShortcut("i", modifiers: [.option, .command])
                Button("") { if !isRunning { confirmDelete = true } }
                    .keyboardShortcut(.delete, modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayName)
                    .font(VermutType.title)
                    .foregroundStyle(Color.Vermut.foreground)
                Spacer(minLength: VermutSpace.s2)
                if isRunning {
                    VermutBadge(
                        kind: .success,
                        text: String(localized: "Running", comment: "Bottle running badge"),
                        showsDot: true
                    )
                }
            }

            Text(metaLine)
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.mutedForeground)

            HStack(spacing: VermutSpace.s2) {
                Button(String(localized: "Run .exe or Installer…", comment: "Primary custom bottle action")) {
                    showFilePicker = true
                }
                .buttonStyle(VermutButtonStyle(kind: .primary))

                Button(String(localized: "Open C: Drive", comment: "Open drive_c")) {
                    openCDrive()
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))

                Button(String(localized: "Settings", comment: "Bottle settings")) {
                    showSettings = true
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))

                Spacer(minLength: VermutSpace.s2)

                Button(String(localized: "Delete Bottle…", comment: "Delete custom bottle")) {
                    confirmDelete = true
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
                .disabled(isRunning)
                .help(
                    isRunning
                    ? String(
                        localized: "Wine is running in this bottle. Quit its programs to delete it.",
                        comment: "Delete blocked help"
                    )
                    : ""
                )
            }

            if isRunning {
                callout(
                    kind: .warning,
                    text: String(
                        localized: "Wine is running in this bottle. Quit its programs to delete it.",
                        comment: "Delete blocked banner"
                    )
                )
            }
        }
    }

    private var metaLine: String {
        guard let bottle else { return "" }
        let engine = WineManager.shared.resolvedCustomEngine(bottle.configuration).userFacingName
        let graphics = WineManager.shared.resolvedCustomGraphics(bottle.configuration)
        let dxmt: String
        if graphics == .dxmt {
            let tag = StoreRecipe.effectiveDXMTVersion(
                bottle.configuration,
                global: appState.configuration
            ).value
            dxmt = "\(graphics.shortLabel) \(tag)"
        } else {
            dxmt = graphics.shortLabel
        }
        let win = BottleWindowsVersion(rawValue: bottle.configuration.windowsVersion)?.displayName
            ?? bottle.configuration.windowsVersion
        let size = ByteFormat.string(sizeBytes)
        return "\(engine) · \(dxmt) · \(win) · \(size)"
    }

    @ViewBuilder
    private var programsSection: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            Text(String(localized: "Programs", comment: "Custom bottle programs section"))
                .font(VermutType.headline)

            let programs = sortedPrograms
            if programs.isEmpty {
                ContentUnavailableView {
                    Label(
                        String(localized: "No programs yet", comment: "Empty programs title"),
                        systemImage: "app.dashed"
                    )
                } description: {
                    Text(
                        String(
                            localized: "Run a Windows installer or .exe to get started.",
                            comment: "Empty programs body"
                        )
                    )
                } actions: {
                    Button(String(localized: "Run .exe or Installer…", comment: "Empty programs CTA")) {
                        showFilePicker = true
                    }
                    .buttonStyle(VermutButtonStyle(kind: .primary))
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                VStack(spacing: VermutSpace.s2) {
                    ForEach(programs) { program in
                        programRow(program)
                    }
                }
            }
        }
    }

    private var sortedPrograms: [BottleProgram] {
        guard let bottle else { return [] }
        return bottle.programs.sorted { lhs, rhs in
            switch (lhs.lastRunAt, rhs.lastRunAt) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    private func programRow(_ program: BottleProgram) -> some View {
        HStack(alignment: .center, spacing: VermutSpace.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(program.displayName)
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
                Text(programSubtitle(program))
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineLimit(1)
            }
            Spacer(minLength: VermutSpace.s2)
            if programIsRunning(program) {
                VermutBadge(
                    kind: .success,
                    text: String(localized: "Running", comment: "Program running"),
                    showsDot: true
                )
                Button(String(localized: "Show in Finder", comment: "Reveal program")) {
                    revealProgram(program)
                }
                .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall))
            } else {
                if let last = program.lastRunAt {
                    Text(relativeDate(last))
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                }
                Button(String(localized: "Run", comment: "Run program")) {
                    runProgram(program)
                }
                .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall))
            }
        }
        .padding(VermutSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous)
                .strokeBorder(Color.Vermut.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))
        .contextMenu {
            Button(String(localized: "Run", comment: "Context run")) { runProgram(program) }
            Button(String(localized: "Show in Finder", comment: "Context reveal")) { revealProgram(program) }
            Divider()
            Button(String(localized: "Remove from List", comment: "Context remove"), role: .destructive) {
                removeProgram(program)
            }
        }
    }

    private func programSubtitle(_ program: BottleProgram) -> String {
        switch program.kind {
        case .shortcut:
            return String(localized: "Shortcut found · Start Menu", comment: "Shortcut subtitle")
        case .installer:
            return String(localized: "Installer · ran once", comment: "Installer subtitle")
        case .launched:
            return program.windowsPath
        }
    }

    private enum CalloutKind { case warning, error }

    private func callout(kind: CalloutKind, text: String) -> some View {
        HStack(alignment: .top, spacing: VermutSpace.s2) {
            Image(systemName: kind == .warning ? "exclamationmark.triangle" : "exclamationmark.circle")
                .foregroundStyle(kind == .warning ? Color.Vermut.warning : Color.Vermut.destructive)
            Text(text)
                .font(VermutType.body)
                .foregroundStyle(
                    kind == .warning
                    ? Color.Vermut.warningSubtleForeground
                    : Color.Vermut.errorSubtleForeground
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VermutSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind == .warning ? Color.Vermut.warningSubtle : Color.Vermut.errorSubtle)
        .overlay(
            RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous)
                .strokeBorder(
                    kind == .warning ? Color.Vermut.warningBorder : Color.Vermut.errorBorder,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))
    }

    private func reload() {
        bottle = appState.customBottle(id: bottleID)
        refreshRunning()
        refreshShortcuts()
        Task.detached {
            let url = PathManager.shared.customBottleURL(id: bottleID)
            let size = BottleSizeCache.shared.size(of: url)
            await MainActor.run { sizeBytes = size }
        }
        warningBanner = nil
        if let free = WineManager.availableFreeBytes(), free < 500_000_000 {
            warningBanner = String(
                localized: "Your disk is almost full. Programs in this bottle may fail.",
                comment: "Low disk warning"
            )
        }
    }

    private func refreshRunning() {
        isRunning = WineManager.shared.isCustomBottleRunning(id: bottleID)
        appState.setCustomBottleRunning(id: bottleID, running: isRunning)
    }

    private func refreshShortcuts() {
        guard var bottle else { return }
        let prefix = PathManager.shared.customPrefixURL(id: bottleID)
        let found = ShortcutScanner.scan(prefix: prefix)
        var changed = false
        for shortcut in found {
            if bottle.programs.contains(where: {
                $0.windowsPath.caseInsensitiveCompare(shortcut.windowsPath) == .orderedSame
            }) { continue }
            bottle.programs.append(
                BottleProgram(
                    displayName: shortcut.displayName,
                    windowsPath: shortcut.windowsPath,
                    kind: .shortcut
                )
            )
            changed = true
        }
        if changed {
            self.bottle = bottle
            appState.updateCustomBottle(bottle)
        }
    }

    private func handlePickedExecutable(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let ext = url.pathExtension.lowercased()
            guard ext == "exe" || ext == "msi" else {
                errorBanner = String(
                    localized: "“\(url.lastPathComponent)” isn’t a Windows program Vermut can run.",
                    comment: "Invalid exe"
                )
                return
            }
            guard url.startAccessingSecurityScopedResource() else {
                errorBanner = String(
                    localized: "“\(url.lastPathComponent)” isn’t a Windows program Vermut can run.",
                    comment: "Invalid exe scoped"
                )
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            runHostExecutable(url)
        case .failure(let error):
            errorBanner = error.localizedDescription
        }
    }

    private func runHostExecutable(_ url: URL) {
        guard var bottle else { return }
        do {
            try WineManager.shared.launchInCustomBottle(
                id: bottleID,
                hostExecutable: url.path,
                config: bottle.configuration
            )
            let windowsPath = ShortcutScanner.windowsPathForLaunch(
                hostPath: url.path,
                prefix: PathManager.shared.customPrefixURL(id: bottleID)
            )
            let kind: BottleProgram.Kind = url.pathExtension.lowercased() == "msi" ||
                url.lastPathComponent.lowercased().contains("setup") ||
                url.lastPathComponent.lowercased().contains("install")
                ? .installer
                : .launched
            if let index = bottle.programs.firstIndex(where: {
                $0.windowsPath.caseInsensitiveCompare(windowsPath) == .orderedSame
                    || $0.displayName.caseInsensitiveCompare(url.deletingPathExtension().lastPathComponent) == .orderedSame
            }) {
                bottle.programs[index].lastRunAt = Date()
                bottle.programs[index].windowsPath = windowsPath
            } else {
                bottle.programs.append(
                    BottleProgram(
                        displayName: url.deletingPathExtension().lastPathComponent,
                        windowsPath: windowsPath,
                        kind: kind,
                        lastRunAt: Date()
                    )
                )
            }
            self.bottle = bottle
            appState.updateCustomBottle(bottle)
            refreshRunning()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { refreshShortcuts() }
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func runProgram(_ program: BottleProgram) {
        guard var bottle else { return }
        let prefix = PathManager.shared.customPrefixURL(id: bottleID)
        let host = windowsPathToHost(program.windowsPath, prefix: prefix)
        do {
            try WineManager.shared.launchInCustomBottle(
                id: bottleID,
                hostExecutable: host?.path ?? program.windowsPath,
                config: bottle.configuration
            )
            if let index = bottle.programs.firstIndex(where: { $0.id == program.id }) {
                bottle.programs[index].lastRunAt = Date()
            }
            self.bottle = bottle
            appState.updateCustomBottle(bottle)
            refreshRunning()
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func programIsRunning(_ program: BottleProgram) -> Bool {
        guard isRunning else { return false }
        let needle = URL(fileURLWithPath: program.windowsPath.replacingOccurrences(of: "\\", with: "/"))
            .lastPathComponent
            .lowercased()
        return PrefixRuntime.processArgumentLines().contains {
            $0.lowercased().contains(needle) && $0.contains(PathManager.shared.customPrefixURL(id: bottleID).path)
        }
    }

    private func revealProgram(_ program: BottleProgram) {
        let prefix = PathManager.shared.customPrefixURL(id: bottleID)
        if let host = windowsPathToHost(program.windowsPath, prefix: prefix) {
            NSWorkspace.shared.activateFileViewerSelecting([host])
        } else {
            openCDrive()
        }
    }

    private func removeProgram(_ program: BottleProgram) {
        guard var bottle else { return }
        bottle.programs.removeAll { $0.id == program.id }
        self.bottle = bottle
        appState.updateCustomBottle(bottle)
    }

    private func openCDrive() {
        let driveC = PathManager.shared.customPrefixURL(id: bottleID).appendingPathComponent("drive_c")
        if FileManager.default.fileExists(atPath: driveC.path) {
            NSWorkspace.shared.open(driveC)
        } else {
            NSWorkspace.shared.open(PathManager.shared.customBottleURL(id: bottleID))
        }
    }

    private func deleteBottle() {
        guard !isRunning else { return }
        do {
            try appState.deleteCustomBottle(id: bottleID)
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func windowsPathToHost(_ windowsPath: String, prefix: URL) -> URL? {
        let normalized = windowsPath
            .replacingOccurrences(of: #"C:\"#, with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "C:/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "\\", with: "/")
        let host = prefix.appendingPathComponent("drive_c").appendingPathComponent(normalized)
        return FileManager.default.fileExists(atPath: host.path) ? host : nil
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Bottle settings sheet (⌥⌘I for custom bottles)

struct BottleSettingsSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let bottle: CustomBottle
    var onSave: (CustomBottle) -> Void

    @State private var config: BottleConfiguration
    @StateObject private var enginesModel = WineEnginesViewModel()

    init(bottle: CustomBottle, onSave: @escaping (CustomBottle) -> Void) {
        self.bottle = bottle
        self.onSave = onSave
        _config = State(initialValue: bottle.configuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s4) {
            Text(String(localized: "Bottle Settings", comment: "Custom bottle settings title"))
                .font(VermutType.headline)
            Text(
                String(
                    localized: "“Automatic” values follow Settings.",
                    comment: "Bottle settings intro"
                )
            )
            .font(VermutType.captionRegular)
            .foregroundStyle(Color.Vermut.mutedForeground)

            Form {
                Picker(String(localized: "Wine engine", comment: "Bottle settings"), selection: $config.engine) {
                    Text(automaticEngine).tag(SettingInheritance.automatic)
                    ForEach(WineEngine.allCases) { engine in
                        Text(engine.userFacingName).tag(engine.rawValue)
                    }
                }
                Picker(String(localized: "Graphics backend", comment: "Bottle settings"), selection: $config.graphicsBackend) {
                    Text(automaticGraphics).tag(SettingInheritance.automatic)
                    ForEach(GraphicsBackend.allCases) { backend in
                        Text(backend.shortLabel).tag(backend.rawValue)
                    }
                }
                if WineManager.shared.resolvedCustomGraphics(config) == .dxmt {
                    Picker(String(localized: "DXMT version", comment: "Bottle settings"), selection: $config.dxmtVersion) {
                        Text(automaticDXMT).tag(SettingInheritance.automatic)
                        ForEach(DXMTVersionManager.shared.installedVersions(), id: \.self) { tag in
                            Text(tag).tag(tag)
                        }
                    }
                }
                Picker(String(localized: "Log level", comment: "Bottle settings"), selection: $config.logLevel) {
                    Text("Automatic").tag(SettingInheritance.automatic)
                    ForEach(WineLogLevel.allCases) { level in
                        Text(level.displayName).tag(level.rawValue)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Open log folder", comment: "Bottle settings")) {
                    let url = PathManager.shared.customBottleLogsURL(id: bottle.id)
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
                Spacer()
                Button(String(localized: "Reset all", comment: "Bottle settings reset")) {
                    config = BottleConfiguration()
                }
                .buttonStyle(VermutButtonStyle(kind: .ghost))
                Button(String(localized: "Done", comment: "Close bottle settings")) {
                    var updated = bottle
                    updated.configuration = config
                    onSave(updated)
                    try? WineManager.shared.saveCustomBottleConfig(config, id: bottle.id)
                    dismiss()
                }
                .buttonStyle(VermutButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(VermutSpace.s6)
        .frame(minWidth: 420)
        .onAppear { enginesModel.refresh() }
    }

    private var automaticEngine: String {
        let name = WineEngine.resolved(from: appState.configuration.defaultEngine).userFacingName
        return "Automatic (\(name))"
    }

    private var automaticGraphics: String {
        let backend = GraphicsBackend(rawValue: appState.configuration.defaultGraphicsBackend) ?? .dxmt
        return "Automatic (\(backend.shortLabel))"
    }

    private var automaticDXMT: String {
        "Automatic (\(appState.configuration.defaultDXMTVersion))"
    }
}

private extension UTType {
    static var exe: UTType { UTType(filenameExtension: "exe") ?? .data }
    static var msi: UTType { UTType(filenameExtension: "msi") ?? .data }
}
