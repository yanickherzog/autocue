// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ACFeatures",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ACFeatures", targets: ["ACFeatures"]),
    ],
    dependencies: [
        .package(path: "../ACCore"),
        .package(path: "../ACDesignSystem"),
    ],
    targets: [
        .target(
            name: "ACFeatures",
            dependencies: ["ACCore", "ACDesignSystem"],
            path: "Sources/ACFeatures"
        ),
        .testTarget(
            name: "ACFeaturesTests",
            dependencies: ["ACFeatures"],
            path: "Tests/ACFeaturesTests"
        ),
    ]
)
