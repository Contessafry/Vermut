import SwiftUI
import CaskLauncherCore

/// Settings › Components › D3DMetal — filled out in the D3DMetal feature commit.
struct D3DMetalSettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            Text("D3DMetal (Apple Game Porting Toolkit)")
                .font(VermutType.headline)
            Text("Required for many DirectX 12 games. Apple’s licence means Vermut cannot bundle it — install GPTK yourself and Vermut will detect it.")
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
