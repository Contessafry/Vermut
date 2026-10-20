import SwiftUI
import AppKit
import CaskLauncherCore

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var filter: LibraryFilter = .all

    private var games: [InstalledGame] {
        let query = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appState.installedGames
            .filter { game in
                switch filter {
                case .all: return true
                case .store(let store): return game.store == store
                }
            }
            .filter { game in
                query.isEmpty || game.name.lowercased().contains(query)
            }
    }

    private var steamCount: Int { appState.installedGames.filter { $0.store == .steam }.count }
    private var epicCount: Int { appState.installedGames.filter { $0.store == .epic }.count }
    private var gogCount: Int { appState.installedGames.filter { $0.store == .gog }.count }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: VermutSpace.s3) {
                    filterPills
                    Spacer(minLength: VermutSpace.s2)
                    sortLabel
                }
                VStack(alignment: .leading, spacing: VermutSpace.s3) {
                    filterPills
                    sortLabel
                }
            }
            .padding(.horizontal, VermutSpace.s6)
            .padding(.top, VermutSpace.s4)
            .padding(.bottom, VermutSpace.s4)

            if games.isEmpty {
                // Fixed-height-free container: the empty state's wrapping text inside a bare
                // VStack + Spacer next to ViewThatFits produced a layout SwiftUI gave up on,
                // blanking the whole window (sidebar included).
                ScrollView {
                    empty
                        .padding(.horizontal, VermutSpace.s6)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: VermutSpace.s4)],
                        spacing: VermutSpace.s5
                    ) {
                        ForEach(games) { game in
                            LibraryGameTile(game: game)
                        }
                    }
                    .padding(.horizontal, VermutSpace.s6)
                    .padding(.bottom, VermutSpace.s6)
                }
            }

            if let first = games.first(where: \.isInstalled) ?? games.first {
                continueBar(first)
            }
        }
        .background(Color.Vermut.background)
        .onAppear {
            appState.refreshLibrary()
            if let store = appState.libraryFilterStore {
                filter = .store(store)
                appState.libraryFilterStore = nil
            }
        }
    }

    private var filterPills: some View {
        HStack(spacing: VermutSpace.s2) {
            pill("All \(appState.installedGames.count)", selected: filter == .all, enabled: true) { filter = .all }
            pill("Steam \(steamCount)", selected: filter == .store(.steam), enabled: steamCount > 0) {
                filter = .store(.steam)
            }
            pill("Epic \(epicCount)", selected: filter == .store(.epic), enabled: epicCount > 0) {
                filter = .store(.epic)
            }
            pill("GOG \(gogCount)", selected: filter == .store(.gog), enabled: gogCount > 0) {
                filter = .store(.gog)
            }
        }
        .onChange(of: appState.installedGames.count) { _, _ in
            if case .store(let store) = filter {
                let count: Int
                switch store {
                case .steam: count = steamCount
                case .epic: count = epicCount
                case .gog: count = gogCount
                }
                if count == 0 { filter = .all }
            }
        }
    }

    private func pill(_ title: String, selected: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(VermutType.callout)
                .foregroundStyle(selected ? Color.Vermut.primaryForeground : Color.Vermut.foreground)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(selected ? Color.Vermut.primary : Color.Vermut.secondary)
                .clipShape(RoundedRectangle(cornerRadius: VermutRadius.xsPlus, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .animation(VermutMotion.selection, value: selected)
    }

    private var sortLabel: some View {
        HStack(spacing: VermutSpace.s1) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .medium))
            Text("Recently added")
                .font(VermutType.callout)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.Vermut.mutedForeground)
        .padding(.horizontal, VermutSpace.s3)
        .frame(height: VermutHeight.button)
        .overlay(
            RoundedRectangle(cornerRadius: VermutRadius.sm, style: .continuous)
                .strokeBorder(Color.Vermut.input, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var empty: some View {
        VermutEmptyState(
            systemImage: "gamecontroller",
            title: appState.installedGames.isEmpty ? "No games in your library yet" : "No games match this filter",
            message: appState.installedGames.isEmpty
                ? "Install Steam or GOG, or sign in to Epic. Owned Epic titles show up here so you can install and play them."
                : "Try another store filter or clear the search field.",
            actionTitle: appState.installedGames.isEmpty ? "Open Stores" : nil,
            action: appState.installedGames.isEmpty ? { appState.section = .stores } : nil
        )
    }

    private func continueBar(_ game: InstalledGame) -> some View {
        HStack(spacing: VermutSpace.s3) {
            Image(systemName: "play.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.Vermut.mutedForeground)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("Continue \(game.name)")
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
                    .lineLimit(1)
                Text(game.isInstalled
                     ? "Installed in the \(game.store.shortName) bottle"
                     : "Owned on \(game.store.shortName) · not installed yet")
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineLimit(1)
            }
            Spacer(minLength: VermutSpace.s2)
            if game.isInstalled {
                Button("Play") { appState.launchGame(game) }
                    .buttonStyle(VermutButtonStyle(kind: .primary, horizontalPadding: VermutSpace.s4))
                    .fixedSize()
            } else {
                Button("Install") { appState.installEpicGame(game) }
                    .buttonStyle(VermutButtonStyle(kind: .primary, horizontalPadding: VermutSpace.s4))
                    .fixedSize()
            }
        }
        .padding(.horizontal, VermutSpace.s6)
        .padding(.vertical, VermutSpace.s3)
        .background(Color.Vermut.card)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.Vermut.border).frame(height: 1)
        }
    }
}

private enum LibraryFilter: Equatable {
    case all
    case store(GameStore)
}

struct LibraryGameTile: View {
    let game: InstalledGame
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            LibraryCoverView(game: game)
                .aspectRatio(4 / 5, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))

            HStack(spacing: VermutSpace.s1) {
                Text(game.name)
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
                    .lineLimit(1)
                Spacer(minLength: 0)
                StoreLogoTile(store: game.store, size: 16)
            }
            HStack {
                if game.isInstalled {
                    VermutBadge(kind: .success, text: "Ready", showsDot: false)
                } else {
                    VermutBadge(kind: .info, text: "Not installed", showsDot: false)
                }
                Spacer()
            }
            
            if let compat = appState.getCompatibility(for: game) {
                CompatibilityBadge(compat: compat)
            }
        }
        .onTapGesture {
            if game.isInstalled {
                appState.launchGame(game)
            } else if game.store == .epic {
                appState.installEpicGame(game)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(game.name), \(game.isInstalled ? "Ready" : "Not installed")")
        .accessibilityHint(game.isInstalled ? "Plays \(game.name)" : "Installs \(game.name)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Cached Steam/Epic/GOG cover with a title placeholder until art arrives.
struct LibraryCoverView: View {
    let game: InstalledGame
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            placeholder
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: game.id) {
            guard !game.coverURLs.isEmpty else { return }
            if let data = await CoverCache.load(urls: game.coverURLs, store: game.store, appId: game.appId) {
                image = NSImage(data: data)
            }
        }
    }

    private var placeholder: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color.Vermut.Neutral.s800,
                    Color.Vermut.Neutral.s700
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(game.name)
                .font(VermutType.headline)
                .foregroundStyle(Color.Vermut.primaryForeground)
                .lineLimit(3)
                .lineSpacing(2)
                .shadow(color: Color.Vermut.Neutral.s950.opacity(0.35), radius: 4, y: 1)
                .padding(VermutSpace.s3)
        }
    }
}
