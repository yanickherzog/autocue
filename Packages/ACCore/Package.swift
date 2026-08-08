// swift-tools-version: 6.1
import PackageDescription

// NOTE: this is a minimal scaffold, not the full M1 workspace/package layout from
// ROADMAP.md. It exists solely to make `Timecode`/`TimecodeFrameRate` (SPEC.md §4.9)
// real, buildable, and unit-tested ahead of schedule per an explicit request to
// verify the drop-frame timecode arithmetic now rather than defer it. The rest of
// ACCore's models/use cases/repository protocols, the other five packages, the
// Xcode workspace, and the App target are still M1's job — do not treat this file's
// existence as M1 being done.
let package = Package(
    name: "ACCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ACCore", targets: ["ACCore"])
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
        )
    ]
)
