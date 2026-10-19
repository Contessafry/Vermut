import SwiftUI
import CaskLauncherCore

enum VermutSpace {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
    static let s12: CGFloat = 48
    static let s16: CGFloat = 64
    static let s24: CGFloat = 96
}

enum VermutRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let xsPlus: CGFloat = 5
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 14
    static let full: CGFloat = 999
}

enum VermutHeight {
    static let button: CGFloat = 28
    static let buttonSmall: CGFloat = 24
    static let buttonLarge: CGFloat = 36
    static let field: CGFloat = 28
    static let sidebarRow: CGFloat = 28
    static let badge: CGFloat = 20
    static let progress: CGFloat = 6
    static let toolbar: CGFloat = 52
    static let formRow: CGFloat = 44
    static let sidebar: CGFloat = 232
    static let thisMac: CGFloat = 340
    static let bottleSide: CGFloat = 320
    static let onboardingPanel: CGFloat = 440
}

enum VermutType {
    static let largeTitle = Font.system(size: 26, weight: .bold)
    static let title = Font.system(size: 22, weight: .bold)
    static let headline = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let bodyEmphasis = Font.system(size: 13, weight: .medium)
    static let callout = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11, weight: .medium)
    static let captionRegular = Font.system(size: 11, weight: .regular)
    static let section = Font.system(size: 11, weight: .semibold)
    static let mono = Font.system(size: 11, design: .monospaced)
    static let buttonLarge = Font.system(size: 14, weight: .medium)
}

enum VermutMotion {
    static let hover = Animation.easeOut(duration: 0.1)
    static let selection = Animation.snappy(duration: 0.15)
    static let panel = Animation.smooth(duration: 0.25)
    static let progress = Animation.linear(duration: 0.3)
}

extension View {
    func vermutContinuous(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    func vermutCard() -> some View {
        padding(VermutSpace.s4)
            .background(Color.Vermut.card)
            .overlay(
                RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous)
                    .strokeBorder(Color.Vermut.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous))
    }

    func vermutReducedMotion(_ reduce: Bool, animation: Animation, value: some Equatable) -> some View {
        self.animation(reduce ? .easeInOut(duration: 0.15) : animation, value: value)
    }
}

enum VermutButtonKind {
    case primary
    case outline
    case ghost
    case destructiveOutline
    case destructiveSolid
}

struct VermutButtonStyle: ButtonStyle {
    var kind: VermutButtonKind = .primary
    var height: CGFloat = VermutHeight.button
    var fillWidth = false
    var radius: CGFloat = VermutRadius.sm
    var font: Font = VermutType.bodyEmphasis
    var horizontalPadding: CGFloat = VermutSpace.s3

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(background(pressed: configuration.isPressed))
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(VermutMotion.hover, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Color.Vermut.primaryForeground
        case .outline: return Color.Vermut.foreground
        case .ghost: return Color.Vermut.mutedForeground
        case .destructiveOutline: return Color.Vermut.errorSubtleForeground
        case .destructiveSolid: return Color.Vermut.destructiveForeground
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary:
            return Color.Vermut.primary.opacity(pressed ? 0.9 : 1)
        case .outline:
            return Color.Vermut.background
        case .ghost:
            return pressed ? Color.Vermut.accent : Color.clear
        case .destructiveOutline:
            return Color.Vermut.background
        case .destructiveSolid:
            return Color.Vermut.destructive
        }
    }

    @ViewBuilder
    private var border: some View {
        switch kind {
        case .outline:
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.Vermut.input, lineWidth: 1)
        case .destructiveOutline:
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.Vermut.errorBorder, lineWidth: 1)
        default:
            EmptyView()
        }
    }
}

enum VermutStatusKind {
    case success
    case warning
    case error
    case info
    case neutral

    var background: Color {
        switch self {
        case .success: return Color.Vermut.successSubtle
        case .warning: return Color.Vermut.warningSubtle
        case .error: return Color.Vermut.errorSubtle
        case .info: return Color.Vermut.infoSubtle
        case .neutral: return Color.Vermut.muted
        }
    }

    var foreground: Color {
        switch self {
        case .success: return Color.Vermut.successSubtleForeground
        case .warning: return Color.Vermut.warningSubtleForeground
        case .error: return Color.Vermut.errorSubtleForeground
        case .info: return Color.Vermut.infoSubtleForeground
        case .neutral: return Color.Vermut.mutedForeground
        }
    }

    var border: Color {
        switch self {
        case .success: return Color.Vermut.successBorder
        case .warning: return Color.Vermut.warningBorder
        case .error: return Color.Vermut.errorBorder
        case .info: return Color.Vermut.infoBorder
        case .neutral: return Color.Vermut.border
        }
    }

    var solid: Color {
        switch self {
        case .success: return Color.Vermut.success
        case .warning: return Color.Vermut.warning
        case .error: return Color.Vermut.destructive
        case .info: return Color.Vermut.info
        case .neutral: return Color.Vermut.mutedForeground
        }
    }
}

struct VermutBadge: View {
    var kind: VermutStatusKind
    var text: String
    var systemImage: String?
    var showsDot = false

    var body: some View {
        HStack(spacing: VermutSpace.s1) {
            if showsDot {
                Circle()
                    .fill(kind.solid)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
            }
            Text(text)
                .font(VermutType.caption)
                .monospacedDigit()
        }
        .foregroundStyle(kind.foreground)
        .padding(.horizontal, VermutSpace.s2)
        .frame(height: VermutHeight.badge)
        .background(kind.background)
        .overlay(
            Capsule()
                .strokeBorder(kind.border, lineWidth: 1)
        )
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct VermutProgressBar: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.Vermut.muted)
                Capsule()
                    .fill(Color.Vermut.info)
                    .frame(width: max(VermutHeight.progress, geo.size.width * clamped))
            }
        }
        .frame(height: VermutHeight.progress)
        .accessibilityValue(Text("\(Int((min(max(value, 0), 1)) * 100)) percent"))
    }
}

struct VermutSearchField: View {
    @Binding var text: String
    var placeholder = "Search games and stores"

    var body: some View {
        HStack(spacing: VermutSpace.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.Vermut.mutedForeground)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.foreground)
            Text("⌘K")
                .font(VermutType.caption)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .padding(.horizontal, VermutSpace.s1)
                .padding(.vertical, 2)
                .background(Color.Vermut.muted)
                .clipShape(RoundedRectangle(cornerRadius: VermutRadius.xs, style: .continuous))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 140, idealWidth: 240, maxWidth: 280)
        .frame(height: VermutHeight.field)
        .layoutPriority(1)
        .background(Color.Vermut.background)
        .overlay(
            RoundedRectangle(cornerRadius: VermutRadius.sm, style: .continuous)
                .strokeBorder(Color.Vermut.input, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: VermutRadius.sm, style: .continuous))
    }
}

/// Logo mark — bottle-with-gamepad from the brand kit iconset (not a drawn stand-in).
struct VermutMarkView: View {
    var height: CGFloat = 22

    var body: some View {
        BrandGlyphView(asset: .vermutMark, size: height)
            .clipShape(RoundedRectangle(cornerRadius: height * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Sidebar wordmark at 15pt from BrandAssets. Original (not a template):
/// dark Bricolage outline in light mode, white outline in dark mode.
struct VermutWordmarkView: View {
    @Environment(\.colorScheme) private var colorScheme
    var height: CGFloat = 15

    private var asset: BrandAsset {
        colorScheme == .dark ? .vermutWordmarkWhite : .vermutWordmark
    }

    var body: some View {
        BrandGlyphView(
            asset: asset,
            size: height,
            width: height * BrandAsset.wordmarkAspect
        )
        .accessibilityHidden(true)
    }
}

struct ContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func measuringContentWidth(_ width: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: ContentWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(ContentWidthKey.self) { width.wrappedValue = $0 }
    }
}

struct StoreInstallControls: View {
    let store: GameStore
    let status: StoreStatus
    var fillWidth = true
    @EnvironmentObject private var appState: AppState

    var body: some View {
        switch status {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: VermutSpace.s2) {
                VermutProgressBar(value: progress)
                cancelButton
            }
        case .installing(.settingUp):
            VStack(alignment: .leading, spacing: VermutSpace.s2) {
                HStack(spacing: VermutSpace.s2) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Setting up…")
                        .font(VermutType.body)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                    Spacer(minLength: 0)
                }
                cancelButton
            }
        case .installing(.awaitingWindow):
            VStack(alignment: .leading, spacing: VermutSpace.s2) {
                VermutBadge(
                    kind: .warning,
                    text: "Finish the installer window",
                    systemImage: "exclamationmark.triangle",
                    showsDot: false
                )
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: VermutSpace.s2) {
                        bringToFrontButton
                        cancelButton
                    }
                    VStack(alignment: .leading, spacing: VermutSpace.s2) {
                        bringToFrontButton
                        cancelButton
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private var cancelButton: some View {
        Button("Cancel") { appState.cancelInstall(store) }
            .buttonStyle(VermutButtonStyle(kind: .outline, fillWidth: fillWidth))
            .help("Cancel this install")
    }

    private var bringToFrontButton: some View {
        Button("Bring to front") { appState.bringInstallerToFront(store) }
            .buttonStyle(VermutButtonStyle(kind: .primary, fillWidth: fillWidth))
            .help("Show the installer window")
    }
}

struct VermutEmptyState: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.Vermut.mutedForeground)
            Text(title)
                .font(VermutType.headline)
                .foregroundStyle(Color.Vermut.foreground)
            Text(message)
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(VermutButtonStyle(kind: .primary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, VermutSpace.s8)
    }
}
