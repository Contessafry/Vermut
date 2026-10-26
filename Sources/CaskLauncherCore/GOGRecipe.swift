import Foundation

/// Known-good GOG Galaxy recipe. Galaxy's Qt UI needs a software renderer;
/// DXMT/DXVK leave a blank window (the reason the store was "Coming soon").
///
/// Install path that works without a working Galaxy UI: drop official GOG
/// Windows offline installers into the bottle (`drive_c/GOG Games` or
/// Galaxy's Games folder). Library scan reads `goggame-*.info`.
public enum GOGRecipe {
    public static let recommendedEngine: WineEngine = .staging

    /// Qt 5/6 + CEF helpers: never try D3D11/Metal.
    public static let softwareEnvironment: [String: String] = [
        "QT_OPENGL": "software",
        "QT_QUICK_BACKEND": "software",
        "QSG_RHI_BACKEND": "software",
        "LIBGL_ALWAYS_SOFTWARE": "1"
    ]

    public static let launchArguments = [
        "--disable-gpu",
        "--disable-gpu-compositing"
    ]

    public static let dllOverrides = "d3d10core,d3d11,d3d12,dxgi,winemetal=builtin"

    /// Wine Direct3D GDI renderer — avoids Qt creating a D3D11 swapchain.
    public static func registryWrites() -> [WineRegOp] {
        [
            .add(WineRegWrite(
                key: "HKCU\\Software\\Wine\\Direct3D",
                value: "renderer",
                data: "gdi"
            ))
        ]
    }

    public static func applySoftwareEnvironment(to environment: inout [String: String]) {
        for (key, value) in softwareEnvironment {
            environment[key] = value
        }
    }
}
