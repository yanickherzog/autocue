@testable import ACCore
import XCTest

final class ISRCNumberTests: XCTestCase {
    func test_isValid_realExampleShape_hyphenated() {
        XCTAssertTrue(ISRCNumber.isValid("CH-A12-26-00001"))
    }

    func test_isValid_plainTwelveCharacters_noHyphens() {
        XCTAssertTrue(ISRCNumber.isValid("CHA122600001"))
    }

    func test_isValid_acceptsLowercaseInput() {
        XCTAssertTrue(ISRCNumber.isValid("ch-a12-26-00001"))
    }

    func test_isValid_rejectsWrongLength() {
        XCTAssertFalse(ISRCNumber.isValid("CH-A12-26-0001"))
    }

    func test_isValid_rejectsDigitsInCountryCode() {
        XCTAssertFalse(ISRCNumber.isValid("C1-A12-26-00001"))
    }

    func test_isValid_rejectsLettersInYear() {
        XCTAssertFalse(ISRCNumber.isValid("CH-A12-XY-00001"))
    }

    func test_isValid_rejectsLettersInDesignation() {
        XCTAssertFalse(ISRCNumber.isValid("CH-A12-26-0000X"))
    }

    func test_isValid_emptyString_isInvalid() {
        XCTAssertFalse(ISRCNumber.isValid(""))
    }

    func test_normalized_fromPlainTwelveCharacters_addsHyphens() {
        XCTAssertEqual(ISRCNumber.normalized("CHA122600001"), "CH-A12-26-00001")
    }

    func test_normalized_fromHyphenatedLowercase_upcasesAndReformats() {
        XCTAssertEqual(ISRCNumber.normalized("ch-a12-26-00001"), "CH-A12-26-00001")
    }

    func test_normalized_nonConformingInput_returnedUppercasedUnchanged() {
        XCTAssertEqual(ISRCNumber.normalized("not-an-isrc"), "NOT-AN-ISRC")
    }
}
