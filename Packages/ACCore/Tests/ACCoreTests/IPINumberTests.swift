@testable import ACCore
import XCTest

/// Real, independently-sourced example IPI Name Numbers, hand-verified
/// against the real CISAC check-digit algorithm `IPINumber.isValid`
/// implements — not fixture data shared with any existing, already-reviewed
/// PDF/XLSX export fixture (confirmed via a full-repository search before
/// this feature was built; see `docs/DECISIONS.md`). The three "Prince"
/// numbers are real, publicly-documented IPI Name Numbers (Wikipedia's
/// "Interested Parties Information" article) — used specifically because
/// they're independently sourced, not invented to make a test pass.
///
/// `grouped(_:)`'s own expected values are confirmed against a real,
/// SUISA-accepted document the project owner directly read (`"00386757500"`
/// → `"00386 75 75 00"`, `IPINumber`'s own doc comment) — not re-derived
/// from `isValid`'s internal base/check structure, which the real display
/// deliberately ignores.
final class IPINumberTests: XCTestCase {
    func test_isValid_realExampleNumber_oneTwoThreeFourFiveSixSevenEightFourSix() {
        XCTAssertTrue(IPINumber.isValid("01234567846"))
    }

    func test_isValid_realExampleNumber_zeroPaddedWithNinetyCheckDigits() {
        XCTAssertTrue(IPINumber.isValid("00123456790"))
    }

    func test_isValid_realDocumentedIPINameNumber_princeOne() {
        XCTAssertTrue(IPINumber.isValid("00045620792"))
    }

    func test_isValid_realDocumentedIPINameNumber_princeTwo() {
        XCTAssertTrue(IPINumber.isValid("00052210040"))
    }

    func test_isValid_realDocumentedIPINameNumber_princeThree() {
        XCTAssertTrue(IPINumber.isValid("00334284961"))
    }

    func test_isValid_acceptsFormattingCharacters_sameDigitsAsPlainString() {
        XCTAssertTrue(IPINumber.isValid("012 34 56 78 46"))
    }

    func test_isValid_wrongCheckDigits_rejected() {
        // Same base (first 9 digits) as the real example above, with the
        // check digits changed from the correct `46` to an arbitrary wrong
        // value.
        XCTAssertFalse(IPINumber.isValid("01234567899"))
    }

    func test_isValid_tooFewDigits_rejected() {
        XCTAssertFalse(IPINumber.isValid("0123456784"))
    }

    func test_isValid_tooManyDigits_rejected() {
        XCTAssertFalse(IPINumber.isValid("012345678461"))
    }

    func test_isValid_empty_rejected() {
        XCTAssertFalse(IPINumber.isValid(""))
    }

    func test_isValid_nonNumericOnly_rejected() {
        XCTAssertFalse(IPINumber.isValid("not-a-number"))
    }

    // MARK: - grouped(_:) — corrected 2026-10-03, twice. The real display
    // (confirmed against the project owner's own real, SUISA-accepted
    // document) groups the full, unmodified 11-digit number `5-2-2-2` —
    // nothing dropped, nothing split out, no hyphen.

    func test_grouped_realSUISADocumentExample_fiveTwoTwoTwo() {
        // The exact real-world evidence this format was confirmed against:
        // the project owner's own real, previously-submitted, SUISA-accepted
        // cue sheet displays this number as "00386 75 75 00".
        XCTAssertEqual(IPINumber.grouped("00386757500"), "00386 75 75 00")
    }

    func test_grouped_elevenDigits_fiveTwoTwoTwo() {
        XCTAssertEqual(IPINumber.grouped("00123456789"), "00123 45 67 89")
    }

    func test_grouped_realDocumentedIPINameNumber_princeOne() {
        XCTAssertEqual(IPINumber.grouped("00045620792"), "00045 62 07 92")
    }

    func test_grouped_realDocumentedIPINameNumber_princeTwo() {
        XCTAssertEqual(IPINumber.grouped("00052210040"), "00052 21 00 40")
    }

    func test_grouped_realDocumentedIPINameNumber_princeThree() {
        XCTAssertEqual(IPINumber.grouped("00334284961"), "00334 28 49 61")
    }

    func test_grouped_acceptsFormattingCharacters_sameDigitsAsPlainString() {
        XCTAssertEqual(IPINumber.grouped("003 342 849 61"), "00334 28 49 61")
    }

    func test_grouped_dropsNoRealDigits_elevenDigitsInAlwaysAppearSomewhereInTheOutput() {
        let raw = "00334284961"
        let output = IPINumber.grouped(raw)
        let outputDigitsOnly = output.filter(\.isNumber)
        XCTAssertEqual(outputDigitsOnly, raw, "every real digit must appear, in order, with none dropped")
    }

    func test_grouped_fiveDigitsOrFewer_oneUngroupedBlock() {
        XCTAssertEqual(IPINumber.grouped("12345"), "12345")
    }

    func test_grouped_moreThanFiveDigits_continuesGroupingByTwoPastTheFirstFive() {
        XCTAssertEqual(IPINumber.grouped("1234567"), "12345 67")
    }

    func test_grouped_nonNumeric_returnsOriginalUnchanged() {
        XCTAssertEqual(IPINumber.grouped("n/a"), "n/a")
    }
}
