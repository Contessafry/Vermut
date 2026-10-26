import SwiftUI
import CaskLauncherCore

/// Library warning for kernel anti-cheat titles (Easy Anti-Cheat / BattlEye).
struct AntiCheatBadge: View {
    let entry: AntiCheatEntry

    var body: some View {
        HStack(alignment: .top, spacing: VermutSpace.s1) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.Vermut.warning)
            Text(entry.libraryWarning)
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.warningSubtleForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel(entry.libraryWarning)
        .help(
            "Source: Are We Anti-Cheat Yet? Kernel-mode EAC and BattlEye almost never run in Wine on macOS."
        )
    }
}
