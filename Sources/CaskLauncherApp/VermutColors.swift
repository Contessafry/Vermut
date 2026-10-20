// Semantic colors from `tokens.json` via named dynamic NSColors.
// `swift build` / `build.sh` do not compile colorsets, so Color("Vermut/…")
// is never used — unnamed NSColors also resolve clear in SwiftUI.
import SwiftUI
import AppKit
import CaskLauncherCore

enum VermutAssets {
    static var bundle: Bundle {
        // Never Bundle.module: its accessor traps when the bundle is missing.
        VermutResources.appBundles.first ?? .main
    }
}

/// Semantic colors. `brand` is for the logo/About/marketing only — never for controls.
/// Red in UI = error: use `destructive` / `errorSubtle*`.
public extension Color {
    enum Vermut {
        public static let background = semantic("background")
        public static let foreground = semantic("foreground")
        public static let card = semantic("card")
        public static let cardForeground = semantic("cardForeground")
        public static let popover = semantic("popover")
        public static let popoverForeground = semantic("popoverForeground")
        public static let primary = semantic("primary")
        public static let primaryForeground = semantic("primaryForeground")
        public static let secondary = semantic("secondary")
        public static let secondaryForeground = semantic("secondaryForeground")
        public static let muted = semantic("muted")
        public static let mutedForeground = semantic("mutedForeground")
        public static let accent = semantic("accent")
        public static let accentForeground = semantic("accentForeground")
        public static let border = semantic("border")
        public static let input = semantic("input")
        public static let ring = semantic("ring")
        public static let sidebar = semantic("sidebar")
        public static let sidebarForeground = semantic("sidebarForeground")
        public static let sidebarPrimary = semantic("sidebarPrimary")
        public static let sidebarPrimaryForeground = semantic("sidebarPrimaryForeground")
        public static let sidebarAccent = semantic("sidebarAccent")
        public static let sidebarAccentForeground = semantic("sidebarAccentForeground")
        public static let sidebarBorder = semantic("sidebarBorder")
        public static let sidebarRing = semantic("sidebarRing")
        public static let success = semantic("success")
        public static let successForeground = semantic("successForeground")
        public static let successSubtle = semantic("successSubtle")
        public static let successSubtleForeground = semantic("successSubtleForeground")
        public static let successBorder = semantic("successBorder")
        public static let warning = semantic("warning")
        public static let warningForeground = semantic("warningForeground")
        public static let warningSubtle = semantic("warningSubtle")
        public static let warningSubtleForeground = semantic("warningSubtleForeground")
        public static let warningBorder = semantic("warningBorder")
        public static let destructive = semantic("destructive")
        public static let destructiveForeground = semantic("destructiveForeground")
        public static let errorSubtle = semantic("errorSubtle")
        public static let errorSubtleForeground = semantic("errorSubtleForeground")
        public static let errorBorder = semantic("errorBorder")
        public static let info = semantic("info")
        public static let infoForeground = semantic("infoForeground")
        public static let infoSubtle = semantic("infoSubtle")
        public static let infoSubtleForeground = semantic("infoSubtleForeground")
        public static let infoBorder = semantic("infoBorder")
        public static let brand = semantic("brand")
        public static let brandForeground = semantic("brandForeground")
        public static let chart1 = semantic("chart1")
        public static let chart2 = semantic("chart2")
        public static let chart3 = semantic("chart3")
        public static let chart4 = semantic("chart4")
        public static let chart5 = semantic("chart5")
        
        public static let green = success
        public static let amber = warning

        /// Raw scales (theme-independent). Prefer semantic tokens above; Brand.* is for logo/About/marketing only.
        public enum Neutral {
            public static let s50 = scale(VermutPalette.catalog.neutral, "50")
            public static let s100 = scale(VermutPalette.catalog.neutral, "100")
            public static let s200 = scale(VermutPalette.catalog.neutral, "200")
            public static let s300 = scale(VermutPalette.catalog.neutral, "300")
            public static let s400 = scale(VermutPalette.catalog.neutral, "400")
            public static let s500 = scale(VermutPalette.catalog.neutral, "500")
            public static let s600 = scale(VermutPalette.catalog.neutral, "600")
            public static let s700 = scale(VermutPalette.catalog.neutral, "700")
            public static let s800 = scale(VermutPalette.catalog.neutral, "800")
            public static let s900 = scale(VermutPalette.catalog.neutral, "900")
            public static let s950 = scale(VermutPalette.catalog.neutral, "950")
        }

        public enum Brand {
            public static let s50 = scale(VermutPalette.catalog.brandScale, "50")
            public static let s100 = scale(VermutPalette.catalog.brandScale, "100")
            public static let s200 = scale(VermutPalette.catalog.brandScale, "200")
            public static let s300 = scale(VermutPalette.catalog.brandScale, "300")
            public static let s400 = scale(VermutPalette.catalog.brandScale, "400")
            public static let s500 = scale(VermutPalette.catalog.brandScale, "500")
            public static let s600 = scale(VermutPalette.catalog.brandScale, "600")
            public static let s700 = scale(VermutPalette.catalog.brandScale, "700")
            public static let s800 = scale(VermutPalette.catalog.brandScale, "800")
            public static let s900 = scale(VermutPalette.catalog.brandScale, "900")
            public static let s950 = scale(VermutPalette.catalog.brandScale, "950")
        }

        private static let namedColors: [String: NSColor] = {
            var map: [String: NSColor] = [:]
            for name in VermutPalette.semanticNames {
                if let swatch = VermutPalette.swatch(name) {
                    map[name] = VermutPalette.namedNSColor(name, swatch: swatch)
                }
            }
            return map
        }()

        private static func semantic(_ name: String) -> Color {
            if let nsColor = namedColors[name] {
                return Color(nsColor: nsColor)
            }
            let rgba = VermutPalette.rgba(name, dark: false) ?? VermutRGBA(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
            return Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
        }

        private static func scale(_ table: [String: String], _ step: String) -> Color {
            let rgb = VermutPalette.parseHex(table[step] ?? "09090B")
            return Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2)
        }
    }
}
