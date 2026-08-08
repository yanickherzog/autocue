// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ACCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ACCore", targets: ["ACCore"]),
    ],
    targets: [
        .target(
            name: "ACCore",
            path: "Sources/ACCore"
        ),
        .testTarget(
            name: "ACCoreTests",
            dependencies: ["ACCore"],
            path: "Tests/ACCoreTests"
        ),
    ]
)
