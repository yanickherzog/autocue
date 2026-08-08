@testable import ACCore
import XCTest

final class PersonTests: XCTestCase {
    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = Person(firstName: "Ada", lastName: "Lovelace")
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_differingID_makesOtherwiseIdenticalPeopleUnequal() {
        let first = Person(id: UUID(), firstName: "Ada", lastName: "Lovelace")
        let second = Person(id: UUID(), firstName: "Ada", lastName: "Lovelace")
        XCTAssertNotEqual(first, second)
    }

    func test_differingLastName_makesPeopleUnequal() {
        let id = UUID()
        let first = Person(id: id, firstName: "Ada", lastName: "Lovelace")
        let second = Person(id: id, firstName: "Ada", lastName: "King")
        XCTAssertNotEqual(first, second)
    }

    func test_fieldsArePreservedExactlyAsInitialized() {
        let id = UUID()
        let address = PostalAddress(
            street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "Switzerland"
        )
        let person = Person(
            id: id,
            firstName: "Ada",
            lastName: "Lovelace",
            ipiNumber: "00123456789",
            address: address,
            email: "ada@example.com",
            swissPerformNumber: "SP-42"
        )

        XCTAssertEqual(person.id, id)
        XCTAssertEqual(person.firstName, "Ada")
        XCTAssertEqual(person.lastName, "Lovelace")
        XCTAssertEqual(person.ipiNumber, "00123456789")
        XCTAssertEqual(person.address, address)
        XCTAssertEqual(person.email, "ada@example.com")
        XCTAssertEqual(person.swissPerformNumber, "SP-42")
    }

    func test_optionalFields_defaultToNil() {
        let person = Person(firstName: "Ada", lastName: "Lovelace")

        XCTAssertNil(person.ipiNumber)
        XCTAssertNil(person.address)
        XCTAssertNil(person.email)
        XCTAssertNil(person.swissPerformNumber)
    }

    func test_omittedID_generatesAFreshUUIDPerInstance() {
        let first = Person(firstName: "Ada", lastName: "Lovelace")
        let second = Person(firstName: "Ada", lastName: "Lovelace")
        XCTAssertNotEqual(first.id, second.id)
    }
}
