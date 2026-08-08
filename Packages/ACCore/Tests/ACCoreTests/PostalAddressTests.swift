@testable import ACCore
import XCTest

final class PostalAddressTests: XCTestCase {
    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = PostalAddress(
            street: "Bahnhofstrasse 1",
            postalCode: "8001",
            city: "Zürich",
            country: "Switzerland"
        )
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_differingAnyField_makesAddressesUnequal() {
        let base = PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "Switzerland")
        let differentStreet = PostalAddress(
            street: "Rue du Rhône 1",
            postalCode: "8001",
            city: "Zürich",
            country: "Switzerland"
        )
        let differentCountry = PostalAddress(
            street: "Bahnhofstrasse 1",
            postalCode: "8001",
            city: "Zürich",
            country: "France"
        )

        XCTAssertNotEqual(base, differentStreet)
        XCTAssertNotEqual(base, differentCountry)
    }

    func test_fieldsArePreservedExactlyAsInitialized() {
        let address = PostalAddress(street: "Via Nassa 1", postalCode: "6900", city: "Lugano", country: "Switzerland")

        XCTAssertEqual(address.street, "Via Nassa 1")
        XCTAssertEqual(address.postalCode, "6900")
        XCTAssertEqual(address.city, "Lugano")
        XCTAssertEqual(address.country, "Switzerland")
    }

    func test_isComplete_allFourPartsFilledIn_isTrue() {
        let address = PostalAddress(street: "Via Nassa 1", postalCode: "6900", city: "Lugano", country: "Switzerland")
        XCTAssertTrue(address.isComplete)
    }

    func test_isComplete_blankStreet_isFalse() {
        let address = PostalAddress(street: "", postalCode: "6900", city: "Lugano", country: "Switzerland")
        XCTAssertFalse(address.isComplete)
    }

    func test_isComplete_whitespaceOnlyPostalCode_isFalse() {
        // Whitespace-only counts as blank, not as "present" — a real address
        // part, not just a non-empty string.
        let address = PostalAddress(street: "Via Nassa 1", postalCode: "   ", city: "Lugano", country: "Switzerland")
        XCTAssertFalse(address.isComplete)
    }

    func test_isComplete_blankCity_isFalse() {
        let address = PostalAddress(street: "Via Nassa 1", postalCode: "6900", city: "", country: "Switzerland")
        XCTAssertFalse(address.isComplete)
    }

    func test_isComplete_blankCountry_isFalse() {
        let address = PostalAddress(street: "Via Nassa 1", postalCode: "6900", city: "Lugano", country: "")
        XCTAssertFalse(address.isComplete)
    }
}
