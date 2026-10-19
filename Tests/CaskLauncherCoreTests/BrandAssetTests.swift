import XCTest
@testable import CaskLauncherCore

final class BrandAssetTests: XCTestCase {
    func testEveryBrandImageResolvesNonNilPNGFromTheBuiltBundle() {
        for asset in BrandAsset.allCases {
            let url = asset.url(preferringExtension: "png")
            XCTAssertNotNil(url, "PNG URL missing for \(asset.rawValue) in the built bundle")
            if let url {
                XCTAssertTrue(
                    url.path.contains("BrandAssets") || url.lastPathComponent.contains(asset.rawValue),
                    "\(asset.rawValue) resolved outside BrandAssets: \(url.path)"
                )
            }
            let data = asset.pngData()
            XCTAssertNotNil(data, "PNG data missing for \(asset.rawValue)")
            XCTAssertTrue(BrandAsset.pngMagicOK(data ?? Data()), "\(asset.rawValue) is not a PNG")
            XCTAssertGreaterThan(data?.count ?? 0, 64, "\(asset.rawValue) PNG is empty")
        }
    }

    func testEveryPackagedFilenameResolvesFromTheBuiltBundle() {
        for asset in BrandAsset.allCases {
            for file in asset.packagedFilenames {
                let url = asset.url(named: file)
                XCTAssertNotNil(url, "\(file) missing from the built bundle")
                let data = url.flatMap { try? Data(contentsOf: $0) }
                XCTAssertNotNil(data, "\(file) unreadable")
                XCTAssertGreaterThan(data?.count ?? 0, 32, "\(file) is empty")
            }
        }
    }

    func testPrefersRetinaPNG() {
        for asset in BrandAsset.allCases {
            XCTAssertEqual(
                asset.url(preferringExtension: "png")?.lastPathComponent,
                "\(asset.rawValue)@2x.png"
            )
        }
    }

    func testStoreLogosHavePDFVectorAssets() {
        for asset: BrandAsset in [.steam, .epic, .gog, .vermutWordmark, .vermutWordmarkWhite] {
            let data = asset.pdfData()
            XCTAssertNotNil(data, "PDF missing for \(asset.rawValue)")
            XCTAssertEqual(data?.prefix(4), Data("%PDF".utf8), "\(asset.rawValue) is not a PDF")
        }
    }

    func testStoreLogosAreTemplateAssetsAndWordmarkIsOriginal() {
        XCTAssertTrue(BrandAsset.steam.isTemplate)
        XCTAssertTrue(BrandAsset.epic.isTemplate)
        XCTAssertTrue(BrandAsset.gog.isTemplate)
        XCTAssertFalse(BrandAsset.vermutWordmark.isTemplate)
        XCTAssertFalse(BrandAsset.vermutWordmarkWhite.isTemplate)
        XCTAssertFalse(BrandAsset.vermutMark.isTemplate)
        XCTAssertTrue(BrandAsset.vermutWordmark.prefersVector)
        XCTAssertTrue(BrandAsset.vermutWordmarkWhite.prefersVector)
        XCTAssertEqual(BrandAsset.wordmarkAspect, 60.04 / 15.0, accuracy: 0.01)
    }

    func testWordmarkBitmapsAreFifteenPointsTall() throws {
        func pngSize(_ data: Data) -> (UInt32, UInt32) {
            let width = UInt32(data[16]) << 24 | UInt32(data[17]) << 16 | UInt32(data[18]) << 8 | UInt32(data[19])
            let height = UInt32(data[20]) << 24 | UInt32(data[21]) << 16 | UInt32(data[22]) << 8 | UInt32(data[23])
            return (width, height)
        }
        for asset: BrandAsset in [.vermutWordmark, .vermutWordmarkWhite] {
            let oneX = try XCTUnwrap(asset.url(named: "\(asset.rawValue).png").flatMap { try? Data(contentsOf: $0) })
            let twoX = try XCTUnwrap(asset.url(named: "\(asset.rawValue)@2x.png").flatMap { try? Data(contentsOf: $0) })
            let (w1, h1) = pngSize(oneX)
            let (_, h2) = pngSize(twoX)
            XCTAssertEqual(h1, 15, "\(asset.rawValue) 1x height")
            XCTAssertEqual(h2, 30, "\(asset.rawValue) @2x height")
            XCTAssertEqual(Double(w1) / Double(h1), BrandAsset.wordmarkAspect, accuracy: 0.05)
        }
    }

    func testGameStoreMapsOntoBrandAssets() {
        XCTAssertEqual(GameStore.steam.brandAsset, .steam)
        XCTAssertEqual(GameStore.epic.brandAsset, .epic)
        XCTAssertEqual(GameStore.gog.brandAsset, .gog)
    }
}
