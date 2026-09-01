// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SingularityDesktop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Singularity", targets: ["SingularityDesktop"])],
    dependencies: [
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.2.0"),
        .package(url: "https://github.com/wisent-ai/wisent-components.git", exact: "0.7.0"),
        .package(url: "https://github.com/wisent-ai/wisent-desktop-auth.git", revision: "de393f399b86140c0bd0121695d2f489d52d3720"),
        .package(url: "https://github.com/wisent-ai/wisent-errors.git", revision: "b01a0c99766b5c6378ecdbf3921108420ba058f1"),
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
