import Foundation
import Network
import SwiftUI

/// Everything macOS may ask about while Vermut sets up and runs stores.
/// Requested up front so no prompt surprises the user mid-install.
enum PermissionStatus: Equatable {
    case notRequested, requesting, granted, denied, skipped, automatic, notNeeded

    var text: String {
        switch self {
        case .notRequested: return "Not asked yet"
        case .requesting: return "Waiting for macOS…"
        case .granted: return "Allowed"
        case .denied: return "Not allowed. You can change this in System Settings › Privacy & Security."
        case .skipped: return "Skipped"
        case .automatic: return "Handled automatically"
        case .notNeeded: return "Not needed"
        }
    }
}

@MainActor
final class LocalNetworkPermission: ObservableObject {
    @Published var status: PermissionStatus = .notRequested
    private var browser: NWBrowser?

    /// Browsing a Bonjour service makes macOS show the Local Network prompt for Vermut;
    /// Wine/Steam processes Vermut starts are covered by the same decision.
    func request() {
        status = .requesting
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_vermut._tcp", domain: nil), using: params)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready: self.status = .granted; self.stop()
                case .waiting(let error), .failed(let error):
                    _ = error  // PolicyDenied (-65570) or no network: either way not usable now
                    self.status = .denied
                    self.stop()
                default: break
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        // If macOS already decided earlier no prompt appears; settle after a while.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if self.status == .requesting { self.status = .granted; self.stop() }
        }
    }

    func skip() { if status == .notRequested { status = .skipped } }

    private func stop() { browser?.cancel(); browser = nil }
}

struct PermissionsStepView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var localNetwork: LocalNetworkPermission

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s4) {
            Text("Before installing anything, here is everything macOS may ask about. Nothing else will pop up later.")
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            row("Rosetta 2", "Runs Windows/Intel code on Apple Silicon. Installed in the next step, no password needed.",
                appState.hasRosetta ? .granted : .automatic)
            row("Local Network", "Steam uses your network for downloads from other computers, Remote Play and in-home streaming.",
                localNetwork.status) {
                Button(localNetwork.status == .notRequested ? "Allow…" : "Ask again") { localNetwork.request() }
                    .buttonStyle(.bordered)
                    .disabled(localNetwork.status == .requesting || localNetwork.status == .granted)
            }
            row("Opening Vermut", "macOS asked once when you first opened Vermut (Gatekeeper). Already done.", .granted)
            row("Administrator password", "Not needed. Everything is installed inside your user folder.", .notNeeded)
            row("Files and folders", "Only files you pick yourself (for example a game installer).", .notNeeded)
            row("Notifications, Accessibility, Automation, Keychain", "Vermut does not use these.", .notNeeded)
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ detail: String, _ status: PermissionStatus,
                     @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .top, spacing: VermutSpace.s3) {
            Image(systemName: icon(status))
                .foregroundStyle(status == .denied ? Color.Vermut.mutedForeground : Color.Vermut.foreground)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: VermutSpace.s1) {
                Text(title).font(VermutType.bodyEmphasis).foregroundStyle(Color.Vermut.foreground)
                Text(detail).font(VermutType.body).foregroundStyle(Color.Vermut.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status.text).font(VermutType.caption).foregroundStyle(Color.Vermut.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: VermutSpace.s2)
            action()
        }
    }

    private func icon(_ s: PermissionStatus) -> String {
        switch s {
        case .granted, .automatic: return "checkmark.circle"
        case .notNeeded: return "minus.circle"
        case .requesting: return "hourglass"
        case .denied, .skipped: return "arrow.uturn.right.circle"
        case .notRequested: return "circle"
        }
    }
}
