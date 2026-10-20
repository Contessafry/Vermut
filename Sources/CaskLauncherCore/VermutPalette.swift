import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// One light/dark swatch from `tokens.json`. Alpha of 0 is treated as missing/clear.
public struct VermutSwatch: Equatable, Sendable, Codable {
    public var light: String
    public var dark: String
    public var lightAlpha: Double?
    public var darkAlpha: Double?

    public init(light: String, dark: String, lightAlpha: Double? = nil, darkAlpha: Double? = nil) {
        self.light = light
        self.dark = dark
        self.lightAlpha = lightAlpha
        self.darkAlpha = darkAlpha
    }

    public func rgba(dark appearanceIsDark: Bool) -> VermutRGBA {
        let hex = appearanceIsDark ? dark : light
        let alpha = appearanceIsDark ? (darkAlpha ?? 1) : (lightAlpha ?? 1)
        let rgb = VermutPalette.parseHex(hex)
        return VermutRGBA(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
    }
}

public struct VermutRGBA: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var isClear: Bool {
        alpha < 0.01
    }
}

public struct VermutColorCatalog: Equatable, Sendable, Codable {
    public var semantic: [String: VermutSwatch]
    public var neutral: [String: String]
    public var brandScale: [String: String]

    public init(
        semantic: [String: VermutSwatch],
        neutral: [String: String],
        brandScale: [String: String]
    ) {
        self.semantic = semantic
        self.neutral = neutral
        self.brandScale = brandScale
    }
}

/// Zinc / semantic palette loaded from `tokens.json` (never the asset catalog).
public enum VermutPalette {
    public static let catalog: VermutColorCatalog = loadCatalog()

    public static var semanticNames: [String] {
        catalog.semantic.keys.sorted()
    }

    public static func swatch(_ name: String) -> VermutSwatch? {
        catalog.semantic[name]
    }

    public static func rgba(_ name: String, dark: Bool) -> VermutRGBA? {
        catalog.semantic[name]?.rgba(dark: dark)
    }

    public static func scaleHex(_ table: [String: String], step: String) -> VermutRGBA? {
        table[step].map { hex in
            let rgb = parseHex(hex)
            return VermutRGBA(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
    }

    /// Logs every token that resolves clear in light or dark. Never traps.
    @discardableResult
    public static func assertAllTokensResolve() -> String {
        var failed: [String] = []
        for name in semanticNames {
            guard let swatch = catalog.semantic[name] else { continue }
            for dark in [false, true] {
                let color = swatch.rgba(dark: dark)
                if color.isClear {
                    failed.append("\(name)/\(dark ? "dark" : "light")")
                }
            }
        }
        for step in catalog.neutral.keys {
            if scaleHex(catalog.neutral, step: step)?.isClear != false {
                failed.append("neutral.\(step)")
            }
        }
        for step in catalog.brandScale.keys {
            if scaleHex(catalog.brandScale, step: step)?.isClear != false {
                failed.append("brand.\(step)")
            }
        }
#if canImport(AppKit)
        failed.append(contentsOf: assertNamedNSColors())
#endif
        let message: String
        if failed.isEmpty {
            message = "Vermut: \(semanticNames.count) tokens.json colors resolved (asset catalog unused)"
        } else {
            message = "Vermut: CLEAR color tokens: \(failed.joined(separator: ", "))"
        }
        // Non-fatal: missing or clear tokens are logged, never crash the app.
        log(message)
        return message
    }

    public static func parseHex(_ raw: String) -> (Double, Double, Double) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard let int = UInt32(value, radix: 16), value.count == 6 else {
            return (0, 0, 0)
        }
        return (
            Double((int >> 16) & 0xFF) / 255,
            Double((int >> 8) & 0xFF) / 255,
            Double(int & 0xFF) / 255
        )
    }

    private static func loadCatalog() -> VermutColorCatalog {
        if let data = tokensJSONData(),
           let catalog = try? JSONDecoder().decode(VermutColorCatalog.self, from: data),
           !catalog.semantic.isEmpty {
            return catalog
        }
        log("Vermut: tokens.json missing; using embedded palette")
        return (try? JSONDecoder().decode(VermutColorCatalog.self, from: Data(embeddedJSON.utf8)))
            ?? VermutColorCatalog(semantic: [:], neutral: [:], brandScale: [:])
    }

    private static func tokensJSONData() -> Data? {
        for bundle in candidateBundles() {
            if let url = bundle.url(forResource: "tokens", withExtension: "json") {
                return try? Data(contentsOf: url)
            }
            if let root = bundle.resourceURL {
                let candidates = [
                    root.appendingPathComponent("tokens.json"),
                    root.appendingPathComponent("CaskLauncherCore_CaskLauncherCore.bundle/tokens.json")
                ]
                for url in candidates {
                    if let data = try? Data(contentsOf: url), !data.isEmpty {
                        return data
                    }
                }
            }
        }
        return Data(embeddedJSON.utf8)
    }

    private static func candidateBundles() -> [Bundle] {
        // Never Bundle.module: its accessor traps when the bundle is missing.
        return [.main] + VermutResources.coreBundles
    }

    private static func log(_ message: String) {
#if canImport(AppKit)
        NSLog("%@", message)
#else
        print(message)
#endif
    }

#if canImport(AppKit)
    private static func assertNamedNSColors() -> [String] {
        var failed: [String] = []
        let appearances = [NSAppearance(named: .aqua), NSAppearance(named: .darkAqua)].compactMap { $0 }
        for name in semanticNames {
            guard let swatch = catalog.semantic[name] else { continue }
            let named = namedNSColor(name, swatch: swatch)
            for appearance in appearances {
                var alpha: CGFloat = 0
                appearance.performAsCurrentDrawingAppearance {
                    named.usingColorSpace(.sRGB)?.getRed(nil, green: nil, blue: nil, alpha: &alpha)
                }
                if alpha < 0.01 {
                    failed.append("ns:\(name)")
                }
            }
        }
        return failed
    }

    public static func namedNSColor(_ name: String, swatch: VermutSwatch) -> NSColor {
        NSColor(name: NSColor.Name("Vermut.\(name)"), dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let color = swatch.rgba(dark: isDark)
            return NSColor(
                srgbRed: color.red,
                green: color.green,
                blue: color.blue,
                alpha: color.alpha
            )
        })
    }
#endif

    /// Same bytes as `tokens.json`, used when the resource is not yet on disk.
    public static let embeddedJSON = """
    {"semantic":{"background":{"light":"#FFFFFF","dark":"#09090B"},"foreground":{"light":"#09090B","dark":"#FAFAFA"},"card":{"light":"#FFFFFF","dark":"#18181B"},"cardForeground":{"light":"#09090B","dark":"#FAFAFA"},"popover":{"light":"#FFFFFF","dark":"#18181B"},"popoverForeground":{"light":"#09090B","dark":"#FAFAFA"},"primary":{"light":"#18181B","dark":"#E4E4E7"},"primaryForeground":{"light":"#FAFAFA","dark":"#18181B"},"secondary":{"light":"#F4F4F5","dark":"#27272A"},"secondaryForeground":{"light":"#18181B","dark":"#FAFAFA"},"muted":{"light":"#F4F4F5","dark":"#27272A"},"mutedForeground":{"light":"#676772","dark":"#9F9FA9"},"accent":{"light":"#F4F4F5","dark":"#27272A"},"accentForeground":{"light":"#18181B","dark":"#FAFAFA"},"border":{"light":"#E4E4E7","dark":"#FFFFFF","darkAlpha":0.1},"input":{"light":"#E4E4E7","dark":"#FFFFFF","darkAlpha":0.15},"ring":{"light":"#71717B","dark":"#9F9FA9"},"sidebar":{"light":"#FAFAFB","dark":"#18181B"},"sidebarForeground":{"light":"#09090B","dark":"#FAFAFA"},"sidebarPrimary":{"light":"#18181B","dark":"#E4E4E7"},"sidebarPrimaryForeground":{"light":"#FAFAFA","dark":"#18181B"},"sidebarAccent":{"light":"#F4F4F5","dark":"#27272A"},"sidebarAccentForeground":{"light":"#18181B","dark":"#FAFAFA"},"sidebarBorder":{"light":"#E4E4E7","dark":"#FFFFFF","darkAlpha":0.1},"sidebarRing":{"light":"#71717B","dark":"#9F9FA9"},"success":{"light":"#018241","dark":"#46B86E"},"successForeground":{"light":"#FAFAFA","dark":"#0D1C11"},"successSubtle":{"light":"#EAFBEF","dark":"#0E2919"},"successSubtleForeground":{"light":"#015D2D","dark":"#7CE0A2"},"successBorder":{"light":"#AEE8C1","dark":"#1F4D32"},"warning":{"light":"#F3B01D","dark":"#F7B828"},"warningForeground":{"light":"#421E00","dark":"#3E1C00"},"warningSubtle":{"light":"#FFF9E7","dark":"#34220B"},"warningSubtleForeground":{"light":"#8B4501","dark":"#FBC959"},"warningBorder":{"light":"#FADB90","dark":"#66420F"},"destructive":{"light":"#D61E17","dark":"#D53328"},"destructiveForeground":{"light":"#FAFAFA","dark":"#FAFAFA"},"errorSubtle":{"light":"#FFF3F1","dark":"#3F1915"},"errorSubtleForeground":{"light":"#B71B14","dark":"#FDA295"},"errorBorder":{"light":"#FDC9C1","dark":"#7B2E25"},"info":{"light":"#1F6DD8","dark":"#539AF2"},"infoForeground":{"light":"#FAFAFA","dark":"#0C182A"},"infoSubtle":{"light":"#EFF6FF","dark":"#14243C"},"infoSubtleForeground":{"light":"#154FAC","dark":"#9AC8FD"},"infoBorder":{"light":"#C0DAFC","dark":"#244574"},"brand":{"light":"#CE003E","dark":"#CE003E"},"brandForeground":{"light":"#FFFFFF","dark":"#FFFFFF"},"chart1":{"light":"#18181B","dark":"#E4E4E7"},"chart2":{"light":"#52525C","dark":"#9F9FA9"},"chart3":{"light":"#9F9FA9","dark":"#52525C"},"chart4":{"light":"#1F6DD8","dark":"#539AF2"},"chart5":{"light":"#018241","dark":"#46B86E"}},"neutral":{"50":"#FAFAFA","100":"#F4F4F5","200":"#E4E4E7","300":"#D4D4D8","400":"#9F9FA9","500":"#71717B","600":"#52525C","700":"#3F3F46","800":"#27272A","900":"#18181B","950":"#09090B"},"brandScale":{"50":"#FFF2F2","100":"#FFE2E2","200":"#FFCACA","300":"#FEA4A6","400":"#FA6F7B","500":"#EA3455","600":"#CE003E","700":"#AB0035","800":"#89002A","900":"#680220","950":"#420313"}}
    """
}
