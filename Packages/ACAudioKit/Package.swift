// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ACAudioKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ACAudioKit", targets: ["ACAudioKit"]),
    ],
    dependencies: [
        .package(path: "../ACCore"),
    ],
    targets: [
        .target(
            name: "ACAudioKit",
            dependencies: ["ACCore"],
            path: "Sources/ACAudioKit"
        ),
        .testTarget(
            name: "ACAudioKitTests",
            dependencies: ["ACAudioKit"],
            path: "Tests/ACAudioKitTests"
        ),
    ]
)
