// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SingularityDesktop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Singularity", targets: ["SingularityDesktop"])],
    dependencies: [
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.1.0"),
        .package(url: "https://github.com/wisent-ai/wisent-components.git", revision: "63aab577abc78c4d1993a711236479dbc2c2571a"),
        .package(url: "https://github.com/wisent-ai/wisent-desktop-auth.git", revision: "3fa84dc99e2a470c06655882de0c536874e4c8c3"),
    ],
    targets: [
        .executableTarget(
            name: "SingularityDesktop",
            dependencies: [
                .product(name: "WisentDesktopUpdate", package: "wisent-desktop-update"),
                .product(name: "WisentDesignSystem", package: "wisent-components"),
                .product(name: "WisentAuth", package: "wisent-desktop-auth"),
            ]
        ),
    ]
)
