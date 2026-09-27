// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ACPersistence",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ACPersistence", targets: ["ACPersistence"]),
    ],
    dependencies: [
        .package(path: "../ACCore"),
        .package(path: "../ACTestSupport"),
    ],
    targets: [
        .target(
            name: "ACPersistence",
            dependencies: ["ACCore"],
            path: "Sources/ACPersistence"
        ),
        .testTarget(
            name: "ACPersistenceTests",
            dependencies: ["ACPersistence", "ACTestSupport"],
            path: "Tests/ACPersistenceTests"
        ),
    ]
)
