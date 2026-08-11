@testable import ACCore
import XCTest

final class LabelTests: XCTestCase {
    private static let sampleAddress = PostalAddress(
        street: "Rue du Rhône 1", postalCode: "1204", city: "Genève", country: "Switzerland"
    )

    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = Label(name: "Universal Music Publishing", address: Self.sampleAddress)
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_differingID_makesOtherwiseIdenticalLabelsUnequal() {
        let first = Label(id: UUID(), name: "Universal Music Publishing", address: Self.sampleAddress)
        let second = Label(id: UUID(), name: "Universal Music Publishing", address: Self.sampleAddress)
        XCTAssertNotEqual(first, second)
    }

    func test_differingName_makesLabelsUnequal() {
        let id = UUID()
        let first = Label(id: id, name: "Universal Music Publishing", address: Self.sampleAddress)
        let second = Label(id: id, name: "Sony Music Publishing", address: Self.sampleAddress)
        XCTAssertNotEqual(first, second)
    }

    func test_fieldsArePreservedExactlyAsInitialized() {
        let id = UUID()
        let label = Label(
            id: id,
            name: "Universal Music Publishing",
            address: Self.sampleAddress,
            ipiNumber: "00987654321",
            kind: .publisher
        )

        XCTAssertEqual(label.id, id)
        XCTAssertEqual(label.name, "Universal Music Publishing")
        XCTAssertEqual(label.address, Self.sampleAddress)
        XCTAssertEqual(label.ipiNumber, "00987654321")
        XCTAssertEqual(label.kind, .publisher)
    }

    func test_optionalFields_defaultToNil() {
        let label = Label(name: "Universal Music Publishing", address: Self.sampleAddress)

        XCTAssertNil(label.ipiNumber)
        XCTAssertNil(label.kind)
    }

    func test_intendedForLabelRoster_defaultsToFalseWhenOmitted() {
        let label = Label(name: "Universal Music Publishing", address: Self.sampleAddress)
        XCTAssertFalse(label.intendedForLabelRoster)
    }

    func test_intendedForLabelRoster_isOverridableExplicitly() {
        let label = Label(name: "Universal Music Publishing", address: Self.sampleAddress, intendedForLabelRoster: true)
        XCTAssertTrue(label.intendedForLabelRoster)
    }

    func test_omittedID_generatesAFreshUUIDPerInstance() {
        let first = Label(name: "Universal Music Publishing", address: Self.sampleAddress)
        let second = Label(name: "Universal Music Publishing", address: Self.sampleAddress)
        XCTAssertNotEqual(first.id, second.id)
    }

    func test_labelKind_allFourCasesAreDistinct() {
        XCTAssertNotEqual(LabelKind.publisher, .productionCompany)
        XCTAssertNotEqual(LabelKind.publisher, .broadcaster)
        XCTAssertNotEqual(LabelKind.publisher, .other)
        XCTAssertNotEqual(LabelKind.productionCompany, .broadcaster)
        XCTAssertNotEqual(LabelKind.productionCompany, .other)
        XCTAssertNotEqual(LabelKind.broadcaster, .other)
    }
}
