import SwiftUI
import CaskLauncherCore

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
                .frame(width: VermutHeight.onboardingPanel)
                .frame(maxHeight: .infinity)
                .background(Color.Vermut.sidebar)
            Rectangle().fill(Color.Vermut.sidebarBorder).frame(width: 1)
            rightPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.Vermut.background)
        }
        .frame(minWidth: 1024, minHeight: 680)
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Image("VermutAppIcon", bundle: VermutAssets.bundle)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: VermutRadius.xl, style: .continuous))
                .accessibilityHidden(true)

            Text("Welcome to Vermut")
                .font(VermutType.largeTitle)
                .foregroundStyle(Color.Vermut.sidebarForeground)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, VermutSpace.s6)

            Text("Play your Windows games on this Mac. Vermut sets up Wine, graphics translation and your stores — no Terminal, no accounts.")
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
                .padding(.top, VermutSpace.s3)
                .frame(maxWidth: 320, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(alignment: .leading, spacing: VermutSpace.s2) {
                Label("Free and open source", systemImage: "heart")
                Label(VermutProject.githubDisplay, systemImage: "link")
            }
            .font(VermutType.captionRegular)
            .foregroundStyle(Color.Vermut.mutedForeground)
            .labelStyle(.titleAndIcon)
        }
        .padding(VermutSpace.s10)
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: VermutSpace.s8) {
                    VStack(alignment: .leading, spacing: VermutSpace.s1) {
                        Text(stepCaption)
                            .font(VermutType.caption)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                        Text(appState.setupFailed ? "Setup failed" : (appState.setupPhase == .permissions ? "Permissions Vermut may need" : "Getting your Mac ready"))
                            .font(VermutType.title)
                            .foregroundStyle(Color.Vermut.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if appState.setupFailed {
                        failureBlock
                    } else if appState.setupPhase == .permissions {
                        PermissionsStepView(localNetwork: appState.localNetwork)
                    } else {
                        VStack(alignment: .leading, spacing: VermutSpace.s6) {
                            stepRow(
                                index: 1,
                                title: "Rosetta 2",
                                detail: "Installed. Lets Intel-only Windows binaries run on Apple Silicon.",
                                state: rosettaState
                            )
                            stepRow(
                                index: 2,
                                title: "Wine engine",
                                detail: wineDetail,
                                state: wineState,
                                progress: wineProgress
                            )
                            storeStep
                        }
                    }
                }
                .padding(.horizontal, VermutSpace.s24)
                .padding(.top, VermutSpace.s16)
                .padding(.bottom, VermutSpace.s10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle().fill(Color.Vermut.border).frame(height: 1)
            HStack(spacing: VermutSpace.s3) {
                Button("Skip for now") {
                    if onPermissions { appState.confirmPermissions() } else { appState.skipOnboarding() }
                }
                .buttonStyle(VermutButtonStyle(kind: .ghost))
                .disabled(!(appState.isSetupComplete || onPermissions))
                .opacity(appState.isSetupComplete || onPermissions ? 1 : 0.5)

                Spacer(minLength: VermutSpace.s2)

                Button {
                    if onPermissions { appState.confirmPermissions() } else { appState.finishOnboarding() }
                } label: {
                    HStack(spacing: VermutSpace.s2) {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .buttonStyle(
                    VermutButtonStyle(
                        kind: .primary,
                        height: VermutHeight.buttonLarge,
                        radius: VermutRadius.md,
                        font: VermutType.buttonLarge,
                        horizontalPadding: VermutSpace.s4
                    )
                )
                .disabled(!(appState.isSetupComplete || onPermissions))
                .opacity(appState.isSetupComplete || onPermissions ? 1 : 0.5)
                .help("Continue to stores")
                .fixedSize()
            }
            .padding(.horizontal, VermutSpace.s24)
            .padding(.vertical, VermutSpace.s10)
        }
    }

    private var failureBlock: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s4) {
            HStack(alignment: .top, spacing: VermutSpace.s2) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.Vermut.destructive)
                VStack(alignment: .leading, spacing: VermutSpace.s1) {
                    Text("Could not finish setup")
                        .font(VermutType.bodyEmphasis)
                        .foregroundStyle(Color.Vermut.errorSubtleForeground)
                    Text(appState.errorMessage ?? "An unknown error occurred.")
                        .font(VermutType.body)
                        .foregroundStyle(Color.Vermut.errorSubtleForeground)
                        .lineSpacing(2)
                }
            }
            .padding(VermutSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.Vermut.errorSubtle)
            .overlay(
                RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous)
                    .strokeBorder(Color.Vermut.errorBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous))

            Button("Retry") {
                Task { await appState.checkSetup() }
            }
            .buttonStyle(VermutButtonStyle(kind: .primary))
        }
    }

    private var storeStep: some View {
        let unlocked = appState.isSetupComplete
        return HStack(alignment: .top, spacing: VermutSpace.s3) {
            stepIndex(3, state: unlocked ? .current : .idle)
            VStack(alignment: .leading, spacing: VermutSpace.s3) {
                Text("Choose your stores")
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
                Text("We’ll create one bottle per store. You can add more later.")
                    .font(VermutType.body)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: VermutSpace.s3) {
                        ForEach(GameStore.allCases) { store in
                            storePick(store)
                                .disabled(!unlocked)
                                .opacity(unlocked ? 1 : 0.6)
                        }
                    }
                    VStack(alignment: .leading, spacing: VermutSpace.s2) {
                        ForEach(GameStore.allCases) { store in
                            storePick(store)
                                .disabled(!unlocked)
                                .opacity(unlocked ? 1 : 0.6)
                        }
                    }
                }
            }
        }
    }

    private func storePick(_ store: GameStore) -> some View {
        if StoreRecipe.isComingSoon(store) {
            return AnyView(comingSoonPick(store))
        }
        return AnyView(availableStorePick(store))
    }

    private func comingSoonPick(_ store: GameStore) -> some View {
        HStack(spacing: VermutSpace.s2) {
            StoreLogoTile(store: store, size: 32)
                .opacity(0.5)
            Text(store.shortName)
                .font(VermutType.bodyEmphasis)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineLimit(1)
            Text("Coming soon")
                .font(VermutType.caption)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineLimit(1)
        }
        .padding(VermutSpace.s2)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.Vermut.border, lineWidth: 1)
        )
        .accessibilityLabel("\(store.shortName), coming soon")
        .help("\(store.shortName) support is coming in a future update.")
    }

    private func availableStorePick(_ store: GameStore) -> some View {
        let selected = appState.onboardingStoreSelection.contains(store)
        return Button {
            if selected {
                appState.onboardingStoreSelection.remove(store)
            } else {
                appState.onboardingStoreSelection.insert(store)
            }
        } label: {
            HStack(spacing: VermutSpace.s2) {
                StoreLogoTile(store: store, size: 32)
                Text(store.shortName)
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
                    .lineLimit(1)
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? Color.Vermut.foreground : Color.Vermut.mutedForeground)
            }
            .padding(.horizontal, VermutSpace.s3)
            .frame(minWidth: 168, minHeight: 48, maxHeight: 48, alignment: .leading)
            .background(Color.Vermut.card)
            .overlay(
                RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous)
                    .strokeBorder(selected ? Color.Vermut.foreground : Color.Vermut.border, lineWidth: 1)
            )
            .shadow(color: selected ? Color.Vermut.foreground.opacity(0.25) : .clear, radius: selected ? 0 : 0)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: VermutRadius.lg + 1, style: .continuous)
                        .strokeBorder(Color.Vermut.foreground, lineWidth: 1)
                        .padding(-1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : VermutMotion.selection, value: selected)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private func stepRow(index: Int, title: String, detail: String, state: StepState, progress: Double? = nil) -> some View {
        HStack(alignment: .top, spacing: VermutSpace.s3) {
            stepIndex(index, state: state)
            VStack(alignment: .leading, spacing: VermutSpace.s2) {
                Text(title)
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
                Text(detail)
                    .font(VermutType.body)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress, state == .current {
                    HStack(spacing: VermutSpace.s3) {
                        VermutProgressBar(value: progress)
                        Text("\(Int(progress * 100))%")
                            .font(VermutType.mono)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                            .monospacedDigit()
                    }
                    .animation(reduceMotion ? nil : VermutMotion.progress, value: progress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stepIndex(_ index: Int, state: StepState) -> some View {
        ZStack {
            Circle()
                .fill(state == .done ? Color.Vermut.success : (state == .current ? Color.Vermut.foreground : Color.Vermut.muted))
                .frame(width: 24, height: 24)
            if state == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.Vermut.successForeground)
            } else {
                Text("\(index)")
                    .font(VermutType.callout)
                    .foregroundStyle(state == .current ? Color.Vermut.primaryForeground : Color.Vermut.mutedForeground)
            }
        }
        .accessibilityLabel(state == .done ? "Step \(index) complete" : "Step \(index)")
    }

    private var onPermissions: Bool { appState.setupPhase == .permissions && !appState.setupFailed }

    private var stepCaption: String {
        if appState.setupFailed { return "Setup" }
        if onPermissions { return "Setup · step 1 of 4" }
        if !appState.isSetupComplete {
            return appState.setupPhase == .rosetta ? "Setup · step 2 of 4" : "Setup · step 3 of 4"
        }
        return "Setup · step 4 of 4"
    }

    private var rosettaState: StepState {
        if appState.setupPhase == .rosetta && !appState.hasRosetta { return .current }
        if appState.hasRosetta || appState.isSetupComplete { return .done }
        return .idle
    }

    private var wineState: StepState {
        if appState.isSetupComplete { return .done }
        if appState.setupPhase == .engine { return .current }
        if appState.setupPhase == .rosetta { return .idle }
        return .idle
    }

    private var wineDetail: String {
        if appState.isSetupComplete {
            return "Installed. \(appState.engineStatusLine)."
        }
        if appState.setupPhase == .engine {
            return appState.setupMessage.isEmpty
                ? "Downloading Wine with DXMT."
                : appState.setupMessage
        }
        return "Downloads Wine with DXMT. About 1–2 GB."
    }

    private var wineProgress: Double? {
        wineState == .current ? appState.setupProgress : nil
    }
}

private enum StepState {
    case idle, current, done
}
