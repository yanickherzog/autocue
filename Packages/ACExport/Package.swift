// swift-tools-version: 6.1
import PackageDescription

/// NOTE: this is a minimal scaffold, not the full M28 XLSX export feature (that's
/// XLSXCueSheetWriter/ExportRepositoryImpl, taking a real Project/Setup/[Cue] and
/// producing the SUISA-shaped output — real feature work, not done here). This
/// exists solely to validate the ONE locked-in architectural dependency decision
/// (CLAUDE.md rule 4: libxlsxwriter as the XLSX writer) with a real, runnable
/// smoke test, ahead of the 27 milestones of downstream work that assume it's
/// viable — see SPEC.md §7 and docs/DECISIONS.md for the full writeup.
let package = Package(
    name: "ACExport",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ACExport", targets: ["ACExport"]),
    ],
    dependencies: [
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
                .product(name: "libxlsxwriter", package: "libxlsxwriter"),
            ],
            path: "Sources/ACExport",
        ),
        .testTarget(
            name: "ACExportTests",
            dependencies: ["ACExport"],
            path: "Tests/ACExportTests",
        ),
    ],
)
