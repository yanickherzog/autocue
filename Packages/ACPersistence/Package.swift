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
    ],
    targets: [
        .target(
            name: "ACPersistence",
            dependencies: ["ACCore"],
            path: "Sources/ACPersistence"
        ),
        .testTarget(
            name: "ACPersistenceTests",
            dependencies: ["ACPersistence"],
            path: "Tests/ACPersistenceTests"
        ),
    ]
)
