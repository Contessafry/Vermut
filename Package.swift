// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vermut",
    platforms: [
        .macOS(.v14)
    ],
    products: {
        var products: [Product] = [
            .library(
                name: "CaskLauncherCore",
                targets: ["CaskLauncherCore"]
            ),
        ]
        #if os(macOS)
        products.insert(
            .executable(
                name: "Vermut",
                targets: ["CaskLauncherApp"]
            ),
            at: 0
        )
        #endif
        return products
    }(),
    targets: {
        var targets: [Target] = [
            .target(
                name: "CaskLauncherCore",
                dependencies: [],
                path: "Sources/CaskLauncherCore",
                resources: [
                    .copy("BrandAssets"),
                    .copy("tokens.json"),
                    .copy("kernel-anticheat.json")
                ],
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency")
                ]
            ),
            .testTarget(
                name: "CaskLauncherCoreTests",
                dependencies: ["CaskLauncherCore"],
                path: "Tests/CaskLauncherCoreTests",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency")
                ]
            ),
        ]
        #if os(macOS)
        targets.insert(
            .executableTarget(
                name: "CaskLauncherApp",
                dependencies: ["CaskLauncherCore"],
                path: "Sources/CaskLauncherApp",
                resources: [
                    .process("Assets.xcassets")
                ],
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency")
                ]
            ),
            at: 0
        )
        #endif
        return targets
    }()
)
