@testable import ACCore
import XCTest

final class PartyResolverTests: XCTestCase {
    private static func makeAddress() -> PostalAddress {
        PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
    }

    func test_resolvingAPerson_returnsFirstAndLastNameJoinedAsDisplayName() {
        let person = Person(firstName: "Anna", lastName: "Muster", ipiNumber: "00123", address: Self.makeAddress())

        let resolved = PartyResolver.resolve(.person(person.id), people: [person], labels: [])

        XCTAssertEqual(
            resolved,
            ResolvedParty(displayName: "Anna Muster", address: Self.makeAddress(), ipiNumber: "00123")
        )
    }

    func test_resolvingAPersonWithNoAddress_returnsNilAddress() {
        let person = Person(firstName: "Anna", lastName: "Muster")

        let resolved = PartyResolver.resolve(.person(person.id), people: [person], labels: [])

        XCTAssertEqual(resolved?.address, nil)
    }

    func test_resolvingALabel_returnsCompanyNameAsDisplayName() {
        let label = Label(name: "Studio AG", address: Self.makeAddress(), ipiNumber: "00456")

        let resolved = PartyResolver.resolve(.label(label.id), people: [], labels: [label])

        XCTAssertEqual(
            resolved,
            ResolvedParty(displayName: "Studio AG", address: Self.makeAddress(), ipiNumber: "00456")
        )
    }

    func test_danglingPersonReference_returnsNil() {
        XCTAssertNil(PartyResolver.resolve(.person(UUID()), people: [], labels: []))
    }

    func test_danglingLabelReference_returnsNil() {
        XCTAssertNil(PartyResolver.resolve(.label(UUID()), people: [], labels: []))
    }

    func test_personIDMatchingAnUnrelatedLabelID_stillResolvesOnlyAgainstPeople() {
        // A .person(id) must never accidentally resolve against `labels`,
        // even if some label happens to share that UUID.
        let id = UUID()
        let person = Person(id: id, firstName: "Anna", lastName: "Muster")
        let label = Label(id: id, name: "Should Not Match", address: Self.makeAddress())

        let resolved = PartyResolver.resolve(.person(id), people: [person], labels: [label])

        XCTAssertEqual(resolved?.displayName, "Anna Muster")
    }
}
