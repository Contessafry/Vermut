import SwiftUI
import WebKit
import CaskLauncherCore

/// In-app Epic login. Legendary's CLI prints `https://legendary.gl/epiclogin`;
/// after sign-in the page is JSON containing `authorizationCode`.
struct EpicAuthSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Sign in to Epic Games"
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: VermutSpace.s3) {
                StoreLogoTile(store: .epic, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Epic Games")
                        .font(VermutType.headline)
                        .foregroundStyle(Color.Vermut.foreground)
                    Text(status)
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .lineLimit(1)
                }
                Spacer(minLength: VermutSpace.s2)
                Button("Cancel") { dismiss() }
                    .buttonStyle(VermutButtonStyle(kind: .ghost))
                    .disabled(isBusy)
            }
            .padding(VermutSpace.s4)

            Rectangle().fill(Color.Vermut.border).frame(height: 1)

            if let error {
                Text(error)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.errorSubtleForeground)
                    .padding(VermutSpace.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            EpicLoginWebView(
                url: LegendaryCLI.loginPageURL,
                onCode: { code in
                    Task { await submit(code) }
                },
                onStatus: { status = $0 }
            )
            .frame(minWidth: 720, minHeight: 520)
        }
        .background(Color.Vermut.background)
        .frame(minWidth: 720, minHeight: 600)
    }

    @MainActor
    private func submit(_ code: String) async {
        guard !isBusy else { return }
        isBusy = true
        status = "Finishing sign-in…"
        error = nil
        do {
            try await appState.completeEpicLogin(code: code)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isBusy = false
            status = "Sign in to Epic Games"
        }
    }
}

struct EpicLoginWebView: NSViewRepresentable {
    let url: URL
    let onCode: (String) -> Void
    let onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onStatus: onStatus)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCode: (String) -> Void
        let onStatus: (String) -> Void
        private var captured = false

        init(onCode: @escaping (String) -> Void, onStatus: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onStatus = onStatus
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url, let code = LegendaryParse.authorizationCode(from: url) {
                capture(code)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onStatus("Waiting for Epic authorization…")
            webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] result, _ in
                guard let self, let text = result as? String else { return }
                if let code = LegendaryParse.authorizationCode(in: text) {
                    self.capture(code)
                }
            }
        }

        private func capture(_ code: String) {
            guard !captured else { return }
            captured = true
            onStatus("Authorization received")
            onCode(code)
        }
    }
}
