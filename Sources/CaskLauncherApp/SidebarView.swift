import SwiftUI
import CaskLauncherCore

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logoRow
                .padding(.horizontal, VermutSpace.s3)
                .padding(.top, VermutSpace.s3)
                .padding(.bottom, VermutSpace.s2)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: VermutSpace.s1) {
                        navRow("Stores", systemImage: "storefront", section: .stores)
                        navRow("Library", systemImage: "gamecontroller", section: .library, count: appState.libraryCount)
                        navRow("Downloads", systemImage: "arrow.down.circle", section: .downloads, count: appState.activeDownloadCount)
                    }
                    .padding(.horizontal, VermutSpace.s3)

                    Text("Bottles")
                        .font(VermutType.section)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .padding(.horizontal, VermutSpace.s4)
                        .padding(.top, VermutSpace.s6)
                        .padding(.bottom, VermutSpace.s2)

                    VStack(alignment: .leading, spacing: VermutSpace.s1) {
                        ForEach(GameStore.allCases) { store in
                            bottleRow(store)
                        }
                    }
                    .padding(.horizontal, VermutSpace.s3)
                    .padding(.bottom, VermutSpace.s4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            engineCard
                .padding(.horizontal, VermutSpace.s3)

            navRow("Settings", systemImage: "gearshape", section: .settings)
                .padding(.horizontal, VermutSpace.s3)
                .padding(.top, VermutSpace.s2)

            Text("v\(appState.appVersion)")
                .font(VermutType.mono)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, VermutSpace.s4)
                .padding(.bottom, VermutSpace.s3)
                .padding(.top, VermutSpace.s1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Color.Vermut.sidebarForeground)
        .background(Color.Vermut.sidebar)
    }

    private var logoRow: some View {
        HStack(spacing: VermutSpace.s2) { // 8pt between mark and wordmark
            VermutMarkView(height: 22)
            VermutWordmarkView(height: 15)
            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vermut")
    }

    private func navRow(_ title: String, systemImage: String, section: AppSection, count: Int? = nil) -> some View {
        let selected = appState.section == section
        return Button {
            appState.section = section
        } label: {
            HStack(spacing: VermutSpace.s2) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? Color.Vermut.foreground : Color.Vermut.mutedForeground)
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(selected ? VermutType.bodyEmphasis : VermutType.body)
                    .foregroundStyle(Color.Vermut.sidebarForeground)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, VermutSpace.s2)
            .frame(height: VermutHeight.sidebarRow)
            .background(selected ? Color.Vermut.sidebarAccent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(VermutMotion.selection, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func bottleRow(_ store: GameStore) -> some View {
        let selected: Bool = {
            if case .bottle(let current) = appState.section { return current == store }
            return false
        }()
        let running = {
            if case .running = appState.status(for: store) { return true }
            return false
        }()
        return Button {
            appState.section = .bottle(store)
        } label: {
            HStack(spacing: VermutSpace.s2) {
                StoreLogoTile(store: store, size: 16)
                Text(store.shortName)
                    .font(selected ? VermutType.bodyEmphasis : VermutType.body)
                    .foregroundStyle(Color.Vermut.sidebarForeground)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if running {
                    Circle()
                        .fill(Color.Vermut.success)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Running")
                }
            }
            .padding(.horizontal, VermutSpace.s2)
            .frame(height: VermutHeight.sidebarRow)
            .background(selected ? Color.Vermut.sidebarAccent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(VermutMotion.selection, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var engineCard: some View {
        HStack(alignment: .top, spacing: VermutSpace.s2) {
            Image(systemName: appState.isSetupComplete ? "checkmark.circle" : "circle.dotted")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(appState.isSetupComplete ? Color.Vermut.success : Color.Vermut.info)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.isSetupComplete ? "Engine ready" : "Engine installing")
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.sidebarForeground)
                    .lineLimit(1)
                Text(appState.engineStatusLine)
                    .font(VermutType.mono)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(VermutSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous)
                .strokeBorder(Color.Vermut.sidebarBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous))
    }
}
