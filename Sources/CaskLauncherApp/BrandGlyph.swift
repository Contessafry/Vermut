import AppKit
import SwiftUI
import CaskLauncherCore

/// Loads store/mark glyphs from copied PNG/PDF files in the app bundle.
/// Asset-catalog SVGs are skipped by `actool` in `./build.sh`, so tiles must
/// not depend on `Image("StoreLogos/…", bundle:)`.
enum BrandGlyph {
    static func nsImage(for asset: BrandAsset) -> NSImage? {
        let sources: [Data?] = asset.prefersVector
            ? [asset.pdfData(), asset.pngData()]
            : [asset.pngData(), asset.pdfData()]
        for data in sources {
            guard let data, let image = NSImage(data: data) else { continue }
            image.isTemplate = asset.isTemplate
            return image
        }
        return nil
    }
}

struct BrandGlyphView: View {
    let asset: BrandAsset
    var size: CGFloat
    var width: CGFloat? = nil
    var inset: CGFloat = 0
    var templateForeground: Color? = nil

    var body: some View {
        Group {
            if let nsImage = BrandGlyph.nsImage(for: asset) {
                if asset.isTemplate {
                    Image(nsImage: nsImage)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .foregroundStyle(templateForeground ?? .white)
                } else {
                    Image(nsImage: nsImage)
                        .renderingMode(.original)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
            }
        }
        .padding(inset)
        .frame(width: width ?? size, height: size)
        .accessibilityHidden(true)
    }
}
