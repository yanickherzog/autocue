@testable import ACCore
import XCTest

final class PartyTests: XCTestCase {
    func test_equatableRoundTrip_copyEqualsOriginal() {
        let id = UUID()
        let original = Party.person(id)
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_samePersonID_areEqual() {
        let id = UUID()
        XCTAssertEqual(Party.person(id), Party.person(id))
    }

    func test_sameLabelID_areEqual() {
        let id = UUID()
        XCTAssertEqual(Party.label(id), Party.label(id))
    }

    func test_differentIDs_areNotEqual() {
        XCTAssertNotEqual(Party.person(UUID()), Party.person(UUID()))
    }

    func test_personAndLabelWithSameUnderlyingID_areNotEqual() {
        // .person and .label are distinct identity kinds — sharing a UUID by
        // coincidence must never make them compare equal.
        let id = UUID()
        XCTAssertNotEqual(Party.person(id), Party.label(id))
    }
}
