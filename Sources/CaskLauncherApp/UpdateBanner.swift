import SwiftUI
import CaskLauncherCore

struct UpdateBanner: View {
    @EnvironmentObject var appState: AppState

    let version: String
    let url: String
    var isPrerelease: Bool = false
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
                        HStack(spacing: VermutSpace.s2) {
                            Text("\(version) is available")
                                .font(VermutType.bodyEmphasis)
                                .foregroundStyle(Color.Vermut.foreground)
                            if isPrerelease {
                                VermutBadge(kind: .info, text: "Beta")
                            }
                        }

                        Text("Update available for Vermut")
                            .font(VermutType.captionRegular)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                    }
                }

                Spacer(minLength: VermutSpace.s3)

                HStack(spacing: VermutSpace.s2) {
                    Button {
                        NSWorkspace.shared.open(URL(string: url)!)
                    } label: {
                        Text("Release notes")
                            .font(VermutType.bodyEmphasis)
                    }
                    .buttonStyle(VermutButtonStyle(kind: .outline))

                    Button {
                        onUpdate()
                    } label: {
                        Text("Update")
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
                    .accessibilityLabel("Dismiss")
                }
            }
        }
        .padding(VermutSpace.s4)
        .background(Color.Vermut.card)
        .cornerRadius(VermutRadius.md)
        .shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)
    }
}
