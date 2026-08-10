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
        .package(path: "../ACTestSupport"),
    ],
    targets: [
        .target(
            name: "ACFeatures",
            dependencies: ["ACCore", "ACDesignSystem"],
            path: "Sources/ACFeatures"
        ),
        .testTarget(
            name: "ACFeaturesTests",
            // ACTestSupport is a .testTarget-only dependency (CLAUDE.md,
            // Naming Conventions) — never a dependency of the ACFeatures
            // .target above. ViewModels are tested against its fakes
            // (InMemoryProjectRepository, etc.), never real SwiftData
            // (CONTRIBUTING.md §5).
            dependencies: ["ACFeatures", "ACTestSupport"],
            path: "Tests/ACFeaturesTests"
        ),
    ]
)
