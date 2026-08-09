// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ACDesignSystem",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ACDesignSystem", targets: ["ACDesignSystem"]),
    ],
    targets: [
        .target(
            name: "ACDesignSystem",
            path: "Sources/ACDesignSystem",
            resources: [
                .copy("Resources/Fonts"),
            ]
        ),
        .testTarget(
            name: "ACDesignSystemTests",
            dependencies: ["ACDesignSystem"],
            path: "Tests/ACDesignSystemTests"
        ),
    ]
)
