import SwiftUI
import CaskLauncherCore

/// Settings › Wine Engines — filled out in the Gcenx engines feature commit.
struct WineEnginesSettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            Text("Wine Engines")
                .font(VermutType.headline)
            Text("Download and manage Vermut Wine and Gcenx WineHQ builds.")
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
        }
    }
}
