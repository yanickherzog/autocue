import ACCore
@testable import ACExport
import XCTest

final class WAFormTemplateRepositoryImplTests: XCTestCase {
    /// A dedicated `UserDefaults` suite per test, never `.standard` — avoids
    /// polluting the real developer machine's defaults and guarantees a
    /// clean slate for every test.
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "WAFormTemplateRepositoryImplTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    /// A dedicated temporary directory per test, never the real Application
    /// Support folder — `WAFormTemplateStorage`'s own doc comment explains
    /// why this injection point exists at all: without it, every test here
    /// would read/write the actual developer machine's real files.
    private func makeStorageDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeRepository(defaults: UserDefaults, storageDirectory: URL) -> WAFormTemplateRepositoryImpl {
        WAFormTemplateRepositoryImpl(defaults: defaults, storageDirectory: storageDirectory)
    }

    private func temporaryPDFURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try Data("%PDF-1.4\n%%EOF".utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func test_currentTemplate_nilWhenNothingHasEverBeenImported() throws {
        let repository = try makeRepository(defaults: makeDefaults(), storageDirectory: makeStorageDirectory())
        XCTAssertNil(repository.currentTemplate())
    }

    func test_importTemplate_storesAndReturnsARealReference_andCopiesTheRealBytes() throws {
        let repository = try makeRepository(defaults: makeDefaults(), storageDirectory: makeStorageDirectory())
        let mainURL = try temporaryPDFURL()
        let continuationURL = try temporaryPDFURL()

        let reference = try repository.importTemplate(mainFormURL: mainURL, continuationFormURL: continuationURL)

        XCTAssertEqual(reference.mainFormFileName, mainURL.lastPathComponent)
        XCTAssertEqual(reference.continuationFormFileName, continuationURL.lastPathComponent)
        let copiedURLs = try XCTUnwrap(repository.templateFileURLs())
        XCTAssertEqual(
            try Data(contentsOf: copiedURLs.mainFormURL),
            try Data(contentsOf: mainURL),
            "the copy's bytes should match the original file's"
        )
        XCTAssertNotEqual(copiedURLs.mainFormURL, mainURL, "a real, separate copy — not the original URL")
    }

    func test_importTemplate_persistsSoASubsequentLookupReturnsTheSameReference() throws {
        let defaults = try makeDefaults()
        let storageDirectory = try makeStorageDirectory()
        let repository = makeRepository(defaults: defaults, storageDirectory: storageDirectory)
        let mainURL = try temporaryPDFURL()
        let continuationURL = try temporaryPDFURL()

        let imported = try repository.importTemplate(mainFormURL: mainURL, continuationFormURL: continuationURL)
        let lookedUp = try XCTUnwrap(
            makeRepository(defaults: defaults, storageDirectory: storageDirectory).currentTemplate()
        )

        XCTAssertEqual(lookedUp.mainFormFileName, imported.mainFormFileName, "mainFormFileName differs")
        XCTAssertEqual(
            lookedUp.continuationFormFileName,
            imported.continuationFormFileName,
            "continuationFormFileName differs"
        )
        // `accuracy:`, not exact equality — confirmed real finding, not a
        // flaky assumption: a `UserDefaults(suiteName:)`-backed store (unlike
        // `.standard`, confirmed separately to round-trip a raw `Double`
        // exactly) loses sub-millisecond precision on a stored
        // `timeIntervalSince1970` once actually written to its backing
        // plist. `importedAt` is a display-only field with no correctness
        // dependency on sub-millisecond precision, so this is an accepted,
        // deliberate tradeoff — field-by-field comparison here (rather than
        // this type's own `Equatable`) exists specifically to isolate and
        // document this one field's real imprecision instead of masking it
        // inside a single opaque `XCTAssertEqual` failure.
        let lookedUpInterval = lookedUp.importedAt.timeIntervalSince1970
        let importedInterval = imported.importedAt.timeIntervalSince1970
        XCTAssertEqual(
            lookedUpInterval,
            importedInterval,
            accuracy: 0.001,
            "importedAt differs: \(lookedUpInterval) vs \(importedInterval)"
        )
    }

    func test_importTemplate_aSecondImport_replacesTheFirstOnDiskAndInMetadata() throws {
        let defaults = try makeDefaults()
        let storageDirectory = try makeStorageDirectory()
        let repository = makeRepository(defaults: defaults, storageDirectory: storageDirectory)
        _ = try repository.importTemplate(mainFormURL: temporaryPDFURL(), continuationFormURL: temporaryPDFURL())

        let secondMainURL = try temporaryPDFURL()
        let secondReference = try repository.importTemplate(
            mainFormURL: secondMainURL,
            continuationFormURL: temporaryPDFURL()
        )

        let current = try XCTUnwrap(repository.currentTemplate())
        // Field-by-field, not `XCTAssertEqual(current, secondReference)` —
        // same real, confirmed `UserDefaults(suiteName:)` sub-millisecond
        // `importedAt` imprecision as
        // `test_importTemplate_persistsSoASubsequentLookupReturnsTheSameReference`
        // (see that test's own comment); asserting full `Equatable` equality
        // here was intermittently flaky for exactly that reason.
        XCTAssertEqual(current.mainFormFileName, secondMainURL.lastPathComponent)
        XCTAssertEqual(current.mainFormFileName, secondReference.mainFormFileName)
        XCTAssertEqual(current.continuationFormFileName, secondReference.continuationFormFileName)
        XCTAssertEqual(
            current.importedAt.timeIntervalSince1970,
            secondReference.importedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        // The real, on-disk copy was actually overwritten, not left as the
        // first import's bytes under the same fixed filename.
        let copiedURLs = try XCTUnwrap(repository.templateFileURLs())
        XCTAssertEqual(try Data(contentsOf: copiedURLs.mainFormURL), try Data(contentsOf: secondMainURL))
    }

    func test_templateFileURLs_nilWhenNothingImported() throws {
        let repository = try makeRepository(defaults: makeDefaults(), storageDirectory: makeStorageDirectory())
        XCTAssertNil(repository.templateFileURLs())
    }

    func test_templateFileURLs_nonNilOnceImported_pointsAtARealReadableFile() throws {
        let repository = try makeRepository(defaults: makeDefaults(), storageDirectory: makeStorageDirectory())
        _ = try repository.importTemplate(mainFormURL: temporaryPDFURL(), continuationFormURL: temporaryPDFURL())

        let urls = try XCTUnwrap(repository.templateFileURLs())

        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.mainFormURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.continuationFormURL.path))
    }

    /// Confirms the real, previously-flagged test-isolation gap stays
    /// closed: two repositories pointed at two different storage
    /// directories never see each other's imported template, the same
    /// isolation `UserDefaults(suiteName:)` already provides for the
    /// metadata half.
    func test_twoRepositoriesWithDifferentStorageDirectories_areFullyIsolated() throws {
        let firstRepository = try makeRepository(defaults: makeDefaults(), storageDirectory: makeStorageDirectory())
        let secondRepository = try makeRepository(defaults: makeDefaults(), storageDirectory: makeStorageDirectory())

        _ = try firstRepository.importTemplate(mainFormURL: temporaryPDFURL(), continuationFormURL: temporaryPDFURL())

        XCTAssertNotNil(firstRepository.currentTemplate())
        XCTAssertNil(secondRepository.currentTemplate())
    }

    func test_currentTemplate_nilWhenMetadataPresentButRealFileMissing() throws {
        let defaults = try makeDefaults()
        let storageDirectory = try makeStorageDirectory()
        let repository = makeRepository(defaults: defaults, storageDirectory: storageDirectory)
        _ = try repository.importTemplate(mainFormURL: temporaryPDFURL(), continuationFormURL: temporaryPDFURL())
        XCTAssertNotNil(repository.currentTemplate())

        // Simulate the real copy being removed out-of-band (e.g. a tampered
        // container) while the metadata still claims a template exists.
        let copiedURLs = try XCTUnwrap(repository.templateFileURLs())
        try FileManager.default.removeItem(at: copiedURLs.mainFormURL)

        XCTAssertNil(repository.currentTemplate(), "metadata alone must never be trusted without the real file")
    }
}
