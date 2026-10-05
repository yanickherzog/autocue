@testable import ACDesignSystem
import AppKit
import XCTest

/// `CueTableView.measuredDetailColumnWidth(headerTitle:)` — regression
/// coverage for a real bug: an earlier version measured against AppKit's
/// *default* `NSTableHeaderCell` font (`.SFNS-Regular` 11pt) instead of the
/// font this `Table` actually draws its headers in (`body`'s own
/// `.font(Theme.Typography.font(.regular, size: 12))` modifier, which
/// propagates into the header title text on this SDK) — "Royalty Split"
/// truncated to "Royalty S…" in the real running app because the computed
/// column width was narrower than the real rendered text.
final class CueTableViewMeasurementTests: XCTestCase {
    /// The real font this `Table` actually draws headers in — same
    /// PostScript name/size `Theme.Typography.font(.regular, size: 12)`
    /// wraps, measured independently here (not by calling the function
    /// under test) so this test can't pass by construction.
    private static func realHeaderFont() -> NSFont {
        Theme.Typography.registerFonts()
        return NSFont(name: Theme.FontWeight.regular.postScriptName, size: 12) ?? NSFont.systemFont(ofSize: 12)
    }

    private static func realTextWidth(_ title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: realHeaderFont()]).width
    }

    /// The exact regression: for every real header title this app uses on
    /// a `detailIconColumn`, the measured column width must never be
    /// smaller than the title's own real text width at the real font —
    /// otherwise the header truncates, exactly as "Royalty Split" did.
    func test_measuredDetailColumnWidth_neverSmallerThanRealTextWidthAtTheRealFont() {
        for title in ["Royalty Split", "Label"] {
            let measured = CueTableView.measuredDetailColumnWidth(headerTitle: title)
            let realWidth = Self.realTextWidth(title)
            XCTAssertGreaterThanOrEqual(
                measured,
                realWidth,
                "\"\(title)\" measured width (\(measured)) is narrower than its real text width " +
                    "(\(realWidth)) at the real header font — it will truncate."
            )
        }
    }

    /// Same assertion, generalized beyond this app's current two titles —
    /// so a future column added to `detailIconColumn` with a longer title
    /// is covered automatically, not only the two titles that exist today.
    func test_measuredDetailColumnWidth_neverSmallerThanRealTextWidth_forArbitraryTitles() {
        for title in ["X", "A Considerably Longer Column Header Than Any Real One", "Royalty Split / Label"] {
            let measured = CueTableView.measuredDetailColumnWidth(headerTitle: title)
            let realWidth = Self.realTextWidth(title)
            XCTAssertGreaterThanOrEqual(measured, realWidth, "\"\(title)\" would truncate at the real header font.")
        }
    }

    /// Confirms the fix measures against the *real* Space Grotesk font, not
    /// the AppKit-default system font the original bug used — regenerating
    /// the exact standalone comparison that found the bug, as an automated
    /// check instead of a one-off script.
    func test_measuredDetailColumnWidth_royaltySplit_accountsForTheRealFontBeingWiderThanTheSystemDefault() {
        let systemFontWidth = ("Royalty Split" as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
        let realFontWidth = Self.realTextWidth("Royalty Split")

        // The real font genuinely is wider than the system font this bug's
        // original (wrong) measurement assumed — otherwise this test
        // wouldn't actually be exercising the fix.
        XCTAssertGreaterThan(realFontWidth, systemFontWidth)

        let measured = CueTableView.measuredDetailColumnWidth(headerTitle: "Royalty Split")
        XCTAssertGreaterThanOrEqual(measured, realFontWidth)
    }
}
