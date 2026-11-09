import SwiftUI
import CaskLauncherCore

struct RosettaBanner: View {
    @EnvironmentObject var appState: AppState

    let onDismiss: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            HStack(alignment: .center, spacing: VermutSpace.s4) {
                HStack(spacing: VermutSpace.s3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.Vermut.warning)

                    VStack(alignment: .leading, spacing: VermutSpace.s1) {
                        Text("Rosetta 2 non è disponibile")
                            .font(VermutType.bodyEmphasis)
                            .foregroundStyle(Color.Vermut.foreground)

                        Text("Un aggiornamento di macOS può rimuovere Rosetta. Senza Rosetta i giochi Steam e Wine potrebbero non avviarsi.")
                            .font(VermutType.captionRegular)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: VermutSpace.s3)

                HStack(spacing: VermutSpace.s2) {
                    Button {
                        onInstall()
                    } label: {
                        if appState.isInstallingRosetta {
                            ProgressView()
                                .controlSize(.small)
                                .frame(minWidth: 120, minHeight: 28)
                        } else {
                            Text("Installa Rosetta")
                                .font(VermutType.bodyEmphasis)
                        }
                    }
                    .buttonStyle(VermutButtonStyle(kind: .primary))
                    .disabled(appState.isInstallingRosetta)

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.Vermut.mutedForeground)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isInstallingRosetta)
                    .accessibilityLabel("Chiudi")
                }
            }

            if let error = appState.rosettaInstallError {
                Text(error)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.errorSubtleForeground)
            }
        }
        .padding(VermutSpace.s4)
        .background(Color.Vermut.card)
        .cornerRadius(VermutRadius.md)
        .shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)
    }
}
