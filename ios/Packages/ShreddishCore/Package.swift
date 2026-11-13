// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShreddishCore",
    defaultLocalization: "fr",
    platforms: [
        .iOS(.v26),
        // Plateforme hôte : `swift test --package-path ios/Packages/ShreddishCore` sans simulateur.
        .macOS(.v15),
    ],
    products: [
        .library(name: "ShreddishCore", targets: ["ShreddishCore"]),
    ],
    targets: [
        .target(
            name: "ShreddishCore",
            resources: [.copy("Resources/ciqual.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ShreddishCoreTests",
            dependencies: ["ShreddishCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
