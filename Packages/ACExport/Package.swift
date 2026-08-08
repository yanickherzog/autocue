// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ACExport",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ACExport", targets: ["ACExport"]),
    ],
    dependencies: [
        .package(path: "../ACCore"),
        // Pinned via SPM's normal semver range, resolved at build/resolve time by
        // Xcode/the developer's machine — this is a build-time dependency fetch,
        // not a runtime network call, so it doesn't conflict with CLAUDE.md's
        // "must run fully offline" constraint (that constraint is about the
        // shipped app's runtime behavior).
        .package(url: "https://github.com/jmcnamara/libxlsxwriter.git", from: "1.2.4"),
    ],
    targets: [
        .target(
            name: "ACExport",
            dependencies: [
                "ACCore",
                .product(name: "libxlsxwriter", package: "libxlsxwriter"),
            ],
            path: "Sources/ACExport"
        ),
        .testTarget(
            name: "ACExportTests",
            dependencies: ["ACExport"],
            path: "Tests/ACExportTests"
        ),
    ]
)
