@testable import ACDesignSystem
import XCTest

/// `ACDesignSystem` Views are verified via SwiftUI previews, not unit tests
/// (`CONTRIBUTING.md` §5/§7, `ROADMAP.md` D5's Testing Requirements) — this file
/// covers only the plain-value tokens and the font resource wiring, neither of
/// which requires rendering a View.
final class ThemeTests: XCTestCase {
    func test_surfaceStyles_areFixedAndSwapped() {
        XCTAssertEqual(Theme.Surface.primary.background, Theme.Colors.white)
        XCTAssertEqual(Theme.Surface.primary.foreground, Theme.Colors.carbonBlack)
        XCTAssertEqual(Theme.Surface.reversed.background, Theme.Colors.carbonBlack)
        XCTAssertEqual(Theme.Surface.reversed.foreground, Theme.Colors.white)
    }

    func test_defaultWindowSize_matchesSpecifiedDimensions() {
        XCTAssertEqual(Theme.Layout.defaultWindowSize, CGSize(width: 1290, height: 800))
    }

    func test_defaultLibraryWindowSize_matchesSpecifiedDimensions() {
        XCTAssertEqual(Theme.Layout.defaultLibraryWindowSize, CGSize(width: 450, height: 600))
    }

    func test_spacingScale_isMonotonicallyIncreasing() {
        let scale = [Theme.Spacing.xs, Theme.Spacing.sm, Theme.Spacing.md, Theme.Spacing.lg, Theme.Spacing.xl]
        XCTAssertEqual(scale, scale.sorted())
        XCTAssertEqual(Set(scale).count, scale.count, "spacing tokens should be distinct values")
    }

    func test_bundledFontWeights_areActuallyPresentInTheResourceBundle() {
        let weights = ["SpaceGrotesk-Regular", "SpaceGrotesk-Medium", "SpaceGrotesk-Bold"]
        for weight in weights {
            XCTAssertNotNil(
                Bundle.module.url(forResource: weight, withExtension: "ttf", subdirectory: "Fonts"),
                "expected \(weight).ttf to be bundled as an ACDesignSystem resource"
            )
        }
    }

    func test_fontRegistration_isIdempotent() {
        // Calling this more than once (here, and implicitly via every `font(_:size:)`
        // call in earlier tests/previews) must not crash or throw.
        Theme.Typography.registerFonts()
        Theme.Typography.registerFonts()
    }
}
