import XCTest
@testable import CaskLauncherCore
#if canImport(AppKit)
import AppKit
#endif

final class VermutPaletteTests: XCTestCase {
    func testTokensJSONMatchesEmbeddedCatalog() throws {
        let fromEmbedded = try JSONDecoder().decode(
            VermutColorCatalog.self,
            from: Data(VermutPalette.embeddedJSON.utf8)
        )
        XCTAssertEqual(
            VermutPalette.catalog.semantic.keys.sorted(),
            fromEmbedded.semantic.keys.sorted()
        )
        XCTAssertEqual(VermutPalette.catalog.semantic.count, fromEmbedded.semantic.count)
        XCTAssertGreaterThan(VermutPalette.semanticNames.count, 40)
        XCTAssertNotNil(VermutPalette.swatch("background"))
        XCTAssertNotNil(VermutPalette.swatch("mutedForeground"))
    }

    func testEveryTokenResolvesToANonClearColorInBothAppearances() throws {
        let message = VermutPalette.assertAllTokensResolve()
        XCTAssertTrue(message.contains("resolved"), message)
        XCTAssertFalse(message.contains("CLEAR"), message)

        for name in VermutPalette.semanticNames {
            let light = try XCTUnwrap(VermutPalette.rgba(name, dark: false), "missing \(name) light")
            let dark = try XCTUnwrap(VermutPalette.rgba(name, dark: true), "missing \(name) dark")
            XCTAssertFalse(light.isClear, "\(name) light is clear")
            XCTAssertFalse(dark.isClear, "\(name) dark is clear")
            XCTAssertGreaterThan(light.alpha, 0.01, "\(name) light alpha")
            XCTAssertGreaterThan(dark.alpha, 0.01, "\(name) dark alpha")
        }

        for step in ["50", "100", "200", "300", "400", "500", "600", "700", "800", "900", "950"] {
            let neutral = try XCTUnwrap(VermutPalette.scaleHex(VermutPalette.catalog.neutral, step: step))
            let brand = try XCTUnwrap(VermutPalette.scaleHex(VermutPalette.catalog.brandScale, step: step))
            XCTAssertFalse(neutral.isClear, "neutral.\(step)")
            XCTAssertFalse(brand.isClear, "brand.\(step)")
        }
    }

    func testPublicMemberwiseInitIsUsableFromOtherModules() {
        let color = VermutRGBA(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        XCTAssertEqual(color.red, 0.09, accuracy: 0.0001)
        XCTAssertEqual(color.green, 0.09, accuracy: 0.0001)
        XCTAssertEqual(color.blue, 0.11, accuracy: 0.0001)
        XCTAssertEqual(color.alpha, 1)
        XCTAssertFalse(color.isClear)

        let catalog = VermutColorCatalog(
            semantic: ["background": VermutSwatch(light: "#FFFFFF", dark: "#09090B")],
            neutral: ["50": "#FAFAFA"],
            brandScale: ["500": "#CE003E"]
        )
        XCTAssertEqual(catalog.semantic["background"]?.dark, "#09090B")
        XCTAssertEqual(catalog.neutral["50"], "#FAFAFA")
        XCTAssertEqual(catalog.brandScale["500"], "#CE003E")
    }

    func testBackgroundIsZincNotClear() throws {
        let light = try XCTUnwrap(VermutPalette.rgba("background", dark: false))
        let dark = try XCTUnwrap(VermutPalette.rgba("background", dark: true))
        XCTAssertEqual(light.red, 1, accuracy: 0.01)
        XCTAssertEqual(dark.red, 9.0 / 255.0, accuracy: 0.02)
        XCTAssertEqual(dark.blue, 11.0 / 255.0, accuracy: 0.02)
    }

#if canImport(AppKit)
    func testNamedDynamicNSColorsAreNotClear() throws {
        for name in VermutPalette.semanticNames {
            let swatch = try XCTUnwrap(VermutPalette.swatch(name))
            let color = VermutPalette.namedNSColor(name, swatch: swatch)
            for appearance in [NSAppearance(named: .aqua), NSAppearance(named: .darkAqua)].compactMap({ $0 }) {
                var alpha: CGFloat = 0
                appearance.performAsCurrentDrawingAppearance {
                    color.usingColorSpace(.sRGB)?.getRed(nil, green: nil, blue: nil, alpha: &alpha)
                }
                XCTAssertGreaterThan(alpha, 0.01, "\(name) NSColor clear in \(appearance.name.rawValue)")
            }
        }
    }
#endif
}
