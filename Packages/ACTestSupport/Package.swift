// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ACTestSupport",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ACTestSupport", targets: ["ACTestSupport"]),
    ],
    dependencies: [
        .package(path: "../ACCore"),
    ],
    targets: [
        .target(
            name: "ACTestSupport",
            dependencies: ["ACCore"],
            path: "Sources/ACTestSupport"
        ),
        .testTarget(
            name: "ACTestSupportTests",
            dependencies: ["ACTestSupport"],
            path: "Tests/ACTestSupportTests"
        ),
    ]
)
