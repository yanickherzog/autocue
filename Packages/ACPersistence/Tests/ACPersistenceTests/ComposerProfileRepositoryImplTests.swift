import ACCore
@testable import ACPersistence
import XCTest

final class ComposerProfileRepositoryImplTests: XCTestCase {
    /// A dedicated `UserDefaults` suite per test, never `.standard` — same
    /// reasoning as `WAFormTemplateRepositoryImplTests` (`ACExport`).
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "ComposerProfileRepositoryImplTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func makeProfile(
        address: PostalAddress? = nil,
        email: String? = nil,
        swissPerformNumber: String? = nil
    ) -> ComposerProfile {
        ComposerProfile(
            firstName: "Ada",
            lastName: "Lovelace",
            ipiNumber: "01234567846",
            address: address,
            email: email,
            swissPerformNumber: swissPerformNumber
        )
    }

    func test_currentProfile_nilWhenNeverSaved() throws {
        let repository = try ComposerProfileRepositoryImpl(defaults: makeDefaults())
        XCTAssertNil(repository.currentProfile())
    }

    func test_saveProfile_minimalFields_roundTrips() throws {
        let repository = try ComposerProfileRepositoryImpl(defaults: makeDefaults())
        let profile = makeProfile()

        try repository.saveProfile(profile)

        XCTAssertEqual(repository.currentProfile(), profile)
    }

    func test_saveProfile_everyOptionalFieldPresent_roundTrips() throws {
        let repository = try ComposerProfileRepositoryImpl(defaults: makeDefaults())
        let address = PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        let profile = makeProfile(address: address, email: "ada@example.com", swissPerformNumber: "SP-1")

        try repository.saveProfile(profile)

        XCTAssertEqual(repository.currentProfile(), profile)
    }

    func test_saveProfile_persistsAcrossASeparateRepositoryInstance() throws {
        let defaults = try makeDefaults()
        let profile = makeProfile()
        try ComposerProfileRepositoryImpl(defaults: defaults).saveProfile(profile)

        let lookedUp = ComposerProfileRepositoryImpl(defaults: defaults).currentProfile()

        XCTAssertEqual(lookedUp, profile)
    }

    func test_saveProfile_aSecondSave_replacesTheFirstEntirely() throws {
        let repository = try ComposerProfileRepositoryImpl(defaults: makeDefaults())
        try repository.saveProfile(makeProfile())

        let replacement = ComposerProfile(firstName: "Grace", lastName: "Hopper", ipiNumber: "00123456790")
        try repository.saveProfile(replacement)

        XCTAssertEqual(repository.currentProfile(), replacement)
    }

    /// Confirms `hasSavedProfile`'s own real reason for existing: without
    /// it, "never saved" and "saved with every optional field blank" would
    /// be indistinguishable purely from absent `UserDefaults` reads.
    func test_saveProfile_withNoOptionalFields_stillDistinguishableFromNeverSaved() throws {
        let repository = try ComposerProfileRepositoryImpl(defaults: makeDefaults())
        try repository.saveProfile(makeProfile())

        XCTAssertNotNil(repository.currentProfile())
    }
}
