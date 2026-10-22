import SwiftUI
import AppKit
import CaskLauncherCore

@main
struct CaskLauncherApp: App {
    @NSApplicationDelegateAdaptor(VermutAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        #if DEBUG
        _ = VermutPalette.assertAllTokensResolve()
        #endif
    }

    var body: some Scene {
        WindowGroup("Vermut") {
            ContentView()
                .environmentObject(appState)
                .tint(Color.Vermut.primary)
                .background(WindowFit())
                .frame(minWidth: 1024, minHeight: 680)
                .frame(idealWidth: 1280, idealHeight: 800)
                .onAppear {
                    appDelegate.appState = appState
                }
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Vermut") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: VermutProject.name,
                            .applicationVersion: VermutProject.version,
                            .version: VermutProject.version,
                            .credits: NSAttributedString(
                                string: "\(VermutProject.tagline)\nOpen-source Windows game store launcher for macOS.\nEpic Games uses Legendary (GPLv3).\nDXMT from v0.80 is LGPL 2.1+ (3Shain/dxmt).\nWine engines are LGPL 2.1+."
                            )
                        ]
                    )
                }
                
                Divider()
                
                Button("Check for Updates…") {
                    Task {
                        await appState.checkForUpdateManually()
                    }
                }
                .disabled(appState.isCheckingForUpdate)
            }
            CommandGroup(after: .appSettings) {
                Button("Settings…") {
                    appState.section = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button(String(localized: "New Bottle…", comment: "File menu new bottle")) {
                    appState.showingNewBottleSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button(String(localized: "Game Settings", comment: "View menu inspector")) {
                    appState.toggleGameSettingsInspector()
                }
                .keyboardShortcut("i", modifiers: [.option, .command])
                .disabled(appState.installedGames.isEmpty)
            }
        }
    }
}

/// Stops Vermut-managed Wine/Steam processes on quit (native Mac apps untouched).
@MainActor
final class VermutAppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        appState?.stopAllManagedWineProcesses()
        // Allow a brief moment for SIGTERM before the process exits.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Enforces the token window size (1280×800 default, 1024×680 minimum).
/// An undersized window squashes the three store cards into icon-only columns.
private struct WindowFit: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { Self.apply(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(view.window) }
    }

    private static func apply(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.titled)
        window.title = "Vermut"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 1024, height: 680)
        window.contentMinSize = NSSize(width: 1024, height: 680)
        window.contentMaxSize = NSSize(width: 10_000, height: 10_000)
        if window.frame.width < 1024 || window.frame.height < 680 {
            window.setContentSize(NSSize(width: 1280, height: 800))
            window.center()
        }
    }
}
