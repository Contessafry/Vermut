import SwiftUI
import CaskLauncherCore

struct UpdateBanner: View {
    @EnvironmentObject var appState: AppState
    
    let version: String
    let url: String
    let onDismiss: () -> Void
    let onUpdate: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: VermutSpace.s4) {
                HStack(spacing: VermutSpace.s3) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.Vermut.info)
                    
                    VStack(alignment: .leading, spacing: VermutSpace.s1) {
                        Text("È disponibile \(version)")
                            .font(VermutType.bodyEmphasis)
                            .foregroundStyle(Color.Vermut.foreground)
                        
                        Text("Aggiornamento disponibile per Vermut")
                            .font(VermutType.captionRegular)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                    }
                }
                
                Spacer(minLength: VermutSpace.s3)
                
                HStack(spacing: VermutSpace.s2) {
                    Button {
                        NSWorkspace.shared.open(URL(string: url)!)
                    } label: {
                        Text("Note di rilascio")
                            .font(VermutType.bodyEmphasis)
                    }
                    .buttonStyle(VermutButtonStyle(kind: .outline))
                    
                    Button {
                        onUpdate()
                    } label: {
                        Text("Aggiorna")
                            .font(VermutType.bodyEmphasis)
                    }
                    .buttonStyle(VermutButtonStyle(kind: .primary))
                    
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
            }
        }
        .padding(VermutSpace.s4)
        .background(Color.Vermut.card)
        .cornerRadius(VermutRadius.md)
        .shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)
    }
}
