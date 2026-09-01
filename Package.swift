// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SingularityDesktop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Singularity", targets: ["SingularityDesktop"])],
    dependencies: [
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.2.0"),
        .package(url: "https://github.com/wisent-ai/wisent-components.git", exact: "0.8.1"),
        .package(url: "https://github.com/wisent-ai/wisent-desktop-auth.git", exact: "0.2.3"),
        .package(url: "https://github.com/wisent-ai/wisent-errors.git", exact: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SingularityDesktop",
            dependencies: [
                .product(name: "WisentDesktopUpdate", package: "wisent-desktop-update"),
                .product(name: "WisentDesignSystem", package: "wisent-components"),
                .product(name: "WisentAuth", package: "wisent-desktop-auth"),
                .product(name: "WisentErrors", package: "wisent-errors"),
            ]
        ),
    ]
)
