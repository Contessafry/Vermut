import SwiftUI
import CaskLauncherCore

struct CompatConsentSheet: View {
    @Environment(\.dismiss) var dismiss
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s6) {
            VStack(alignment: .leading, spacing: VermutSpace.s2) {
                Text("Help improve game compatibility")
                    .font(VermutType.title)
                    .foregroundStyle(Color.Vermut.foreground)
                
                Text("Share anonymous game performance reports with the Vermut community.")
                    .font(VermutType.body)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            VStack(alignment: .leading, spacing: VermutSpace.s3) {
                FeatureRow(icon: "chart.bar.fill", title: "Anonymous data", description: "No personal information collected")
                FeatureRow(icon: "arrow.up.circle.fill", title: "Opt-in only", description: "You choose when to share")
                FeatureRow(icon: "gearshape.fill", title: "Toggle anytime", description: "Change your mind in Settings")
            }
            
            Divider()
                .background(Color.Vermut.border)
            
            VStack(alignment: .leading, spacing: VermutSpace.s2) {
                Text("What's shared")
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
                
                Text("Game name, store, Wine engine, graphics layer, macOS version, Apple chip, session length, and whether the game ran well. No IP addresses or device identifiers are stored.")
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: VermutSpace.s4)
            
            HStack(spacing: VermutSpace.s3) {
                Button("Not now") {
                    onDecline()
                    dismiss()
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
                
                Button("Share anonymously") {
                    onAccept()
                    dismiss()
                }
                .buttonStyle(VermutButtonStyle(kind: .primary))
            }
        }
        .padding(VermutSpace.s6)
        .frame(width: 480, height: 520)
        .background(Color.Vermut.background)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: VermutSpace.s3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.Vermut.foreground)
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
                
                Text(description)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
            }
        }
    }
}
