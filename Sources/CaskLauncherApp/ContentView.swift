import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CaskLauncherCore

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            if shouldShowOnboarding {
                OnboardingView()
            } else if appState.isCheckingSetup && !appState.isSetupComplete {
                SetupSplashView()
            } else {
                AppShell(searchFocused: $searchFocused)
            }
        }
        .background(Color.Vermut.background)
        .frame(minWidth: 1024, minHeight: 680)
        .alert("Something went wrong", isPresented: errorPresented) {
            Button("OK", role: .cancel) {
                appState.errorMessage = nil
            }
        } message: {
            if let error = appState.errorMessage {
                Text(error)
            }
        }
        .alert(appState.infoAlertTitle, isPresented: infoPresented) {
            Button("OK", role: .cancel) {
                appState.dismissInfoAlert()
            }
        } message: {
            if let info = appState.infoAlertMessage {
                Text(info)
            }
        }
        .fileImporter(
            isPresented: $appState.showingFilePicker,
            allowedContentTypes: [.item]
        ) { result in
            switch result {
            case .success(let url):
                appState.launchExecutable(at: url)
            case .failure(let error):
                appState.errorMessage = error.localizedDescription
            }
        }
    }

    private var shouldShowOnboarding: Bool {
        appState.setupFailed || appState.showOnboarding
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil && appState.isSetupComplete && !appState.showOnboarding },
            set: { if !$0 { appState.errorMessage = nil } }
        )
    }

    private var infoPresented: Binding<Bool> {
        Binding(
            get: { appState.infoAlertMessage != nil && appState.isSetupComplete && !appState.showOnboarding },
            set: { if !$0 { appState.dismissInfoAlert() } }
        )
    }
}

struct SetupSplashView: View {
    var body: some View {
        VStack(spacing: VermutSpace.s4) {
            VermutMarkView(height: 48)
            VermutWordmarkView(height: 18)
            ProgressView()
                .controlSize(.small)
                .padding(.top, VermutSpace.s2)
            Text("Starting…")
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Vermut.background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Starting Vermut")
    }
}

struct AppShell: View {
    @EnvironmentObject var appState: AppState
    var searchFocused: FocusState<Bool>.Binding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: 200,
                    ideal: VermutHeight.sidebar,
                    max: 280
                )
        } detail: {
            NavigationStack {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.Vermut.background)
                    .navigationTitle("")
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            VermutSearchField(text: $appState.searchQuery)
                                .focused(searchFocused)
                                .onExitCommand { searchFocused.wrappedValue = false }
                                .frame(minWidth: 160, idealWidth: 240, maxWidth: 280)
                            
                            Button {
                                appState.showingFilePicker = true
                            } label: {
                                Label("Run .exe", systemImage: "doc.badge.gearshape")
                            }
                            .labelStyle(.titleAndIcon)
                            .help("Run a Windows executable in a custom bottle")
                            .accessibilityLabel("Run .exe")
                            .accessibilityHint("Choose a Windows executable to run in a custom bottle")
                        }
                    }
                    .background {
                        Button("Focus search") {
                            searchFocused.wrappedValue = true
                        }
                        .keyboardShortcut("k", modifiers: .command)
                        .opacity(0)
                        .accessibilityHidden(true)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 0) {
                            if let update = appState.availableUpdate {
                                UpdateBanner(
                                    version: update.version,
                                    url: update.url,
                                    isPrerelease: update.isPrerelease,
                                    onDismiss: { appState.dismissUpdate() },
                                    onUpdate: { appState.performUpdate() }
                                )
                                .padding(.horizontal, VermutSpace.s6)
                                .padding(.top, VermutSpace.s3)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            
                            if let session = appState.compatFeedbackSession {
                                CompatFeedbackBanner(
                                    session: session,
                                    autoDetectedCrash: appState.compatFeedbackAutoDetectedCrash,
                                    onDismiss: { appState.dismissCompatFeedback() }
                                )
                                .padding(VermutSpace.s6)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.Vermut.background)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : VermutMotion.panel, value: appState.section)
        .animation(VermutMotion.panel, value: appState.availableUpdate?.version)
        .animation(VermutMotion.panel, value: appState.compatFeedbackSession)
        .sheet(item: $appState.bottleToDelete) { store in
            DeleteBottleSheet(store: store) {
                appState.bottleToDelete = nil
                appState.resetStore(store)
            } onCancel: {
                appState.bottleToDelete = nil
            }
        }
        .sheet(isPresented: $appState.showingEpicAuth) {
            EpicAuthSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showingNewBottleSheet) {
            NewBottleSheet()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.section {
        case .stores:
            StoresView()
        case .library:
            LibraryView()
        case .downloads:
            DownloadsView()
        case .bottle(let store):
            BottleDetailView(store: store)
        case .customBottle(let id):
            CustomBottleDetailView(bottleID: id)
        case .settings:
            SettingsView()
        }
    }
}
