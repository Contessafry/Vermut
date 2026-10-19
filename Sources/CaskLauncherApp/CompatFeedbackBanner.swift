import SwiftUI
import CaskLauncherCore

struct CompatFeedbackBanner: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedResult: CompatibilityResult?
    @State private var note: String = ""
    @State private var isSubmitting = false
    
    let session: GameSession
    let autoDetectedCrash: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: VermutSpace.s4) {
                VStack(alignment: .leading, spacing: VermutSpace.s2) {
                    Text("How did \(session.gameName ?? "this game") run?")
                        .font(VermutType.bodyEmphasis)
                        .foregroundStyle(Color.Vermut.foreground)
                    
                    if autoDetectedCrash {
                        HStack(spacing: VermutSpace.s2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.Vermut.amber)
                            
                            Text("Game exited quickly")
                                .font(VermutType.captionRegular)
                                .foregroundStyle(Color.Vermut.mutedForeground)
                        }
                    }
                }
                
                Spacer(minLength: VermutSpace.s3)
                
                HStack(spacing: VermutSpace.s2) {
                    ForEach(CompatibilityResult.allCases, id: \.self) { result in
                        Button {
                            selectedResult = result
                        } label: {
                            Text(resultEmoji(result))
                                .font(.system(size: 20))
                                .frame(width: 36, height: 36)
                                .background(
                                    selectedResult == result
                                        ? resultColor(result).opacity(0.15)
                                        : Color.Vermut.muted.opacity(0.5)
                                )
                                .cornerRadius(VermutRadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: VermutRadius.sm)
                                        .stroke(
                                            selectedResult == result
                                                ? resultColor(result)
                                                : Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(result.displayName)
                    }
                }
                
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            
            if selectedResult != nil {
                VStack(alignment: .leading, spacing: VermutSpace.s3) {
                    Divider()
                        .background(Color.Vermut.border)
                        .padding(.top, VermutSpace.s3)
                    
                    HStack(alignment: .top, spacing: VermutSpace.s3) {
                        VStack(alignment: .leading, spacing: VermutSpace.s1) {
                            TextField("Optional note (280 chars max)", text: $note, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(VermutType.body)
                                .lineLimit(2...3)
                                .frame(maxWidth: .infinity)
                                .onChange(of: note) { _, newValue in
                                    if newValue.count > 280 {
                                        note = String(newValue.prefix(280))
                                    }
                                }
                            
                            Text("\(note.count)/280")
                                .font(VermutType.captionRegular)
                                .foregroundStyle(Color.Vermut.mutedForeground)
                        }
                        
                        Button {
                            submitReport()
                        } label: {
                            if isSubmitting {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 80, height: 32)
                            } else {
                                Text("Submit")
                                    .font(VermutType.bodyEmphasis)
                                    .frame(width: 80, height: 32)
                            }
                        }
                        .buttonStyle(VermutButtonStyle(kind: .primary))
                        .disabled(isSubmitting)
                    }
                }
            }
        }
        .padding(VermutSpace.s4)
        .background(Color.Vermut.card)
        .cornerRadius(VermutRadius.md)
        .shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)
        .onAppear {
            if autoDetectedCrash {
                selectedResult = .broken
            }
        }
    }
    
    private func resultEmoji(_ result: CompatibilityResult) -> String {
        switch result {
        case .perfect: return "✓"
        case .issues: return "~"
        case .broken: return "✗"
        }
    }
    
    private func resultColor(_ result: CompatibilityResult) -> Color {
        switch result {
        case .perfect: return Color.Vermut.green
        case .issues: return Color.Vermut.amber
        case .broken: return Color.Vermut.destructive
        }
    }
    
    private func submitReport() {
        guard let result = selectedResult else { return }
        
        isSubmitting = true
        
        let report = CompatibilityReport(
            store: session.store.identifier,
            gameId: session.gameId,
            gameName: session.gameName,
            vermutVersion: VermutProject.version,
            engine: session.engine,
            graphics: session.graphics,
            macOS: osVersion(),
            chip: chipName(),
            playMinutes: session.playMinutes,
            result: result.rawValue,
            autoDetectedCrash: autoDetectedCrash ? true : nil,
            note: note.isEmpty ? nil : note
        )
        
        if let url = CompatibilityService.shared.generateGitHubIssueURL(report: report) {
            NSWorkspace.shared.open(url)
        }
        
        onDismiss()
    }
    
    private func osVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }
    
    private func chipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &machine, &size, nil, 0)
        let brand = String(cString: machine)
        
        if brand.contains("Apple M") {
            let components = brand.components(separatedBy: " ")
            for (i, component) in components.enumerated() {
                if component.hasPrefix("M"), i + 1 < components.count {
                    return component + " " + components[i + 1]
                }
            }
            return "Apple Silicon"
        }
        
        return "Apple Silicon"
    }
}
