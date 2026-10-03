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

    private func temporaryPDFURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try Data("%PDF-1.4\n%%EOF".utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func test_currentTemplate_nilWhenNothingHasEverBeenImported() throws {
        let repository = try WAFormTemplateRepositoryImpl(defaults: makeDefaults())
        XCTAssertNil(repository.currentTemplate())
    }

    func test_importTemplate_storesAndReturnsARealReference() throws {
        let repository = try WAFormTemplateRepositoryImpl(defaults: makeDefaults())
        let mainURL = try temporaryPDFURL()
        let continuationURL = try temporaryPDFURL()

        let reference = try repository.importTemplate(mainFormURL: mainURL, continuationFormURL: continuationURL)

        XCTAssertFalse(reference.mainFormBookmark.isEmpty)
        XCTAssertFalse(reference.continuationFormBookmark.isEmpty)
        XCTAssertEqual(reference.mainFormFileName, mainURL.lastPathComponent)
        XCTAssertEqual(reference.continuationFormFileName, continuationURL.lastPathComponent)
    }

    func test_importTemplate_persistsSoASubsequentLookupReturnsTheSameReference() throws {
        let defaults = try makeDefaults()
        let repository = WAFormTemplateRepositoryImpl(defaults: defaults)
        let mainURL = try temporaryPDFURL()
        let continuationURL = try temporaryPDFURL()

        let imported = try repository.importTemplate(mainFormURL: mainURL, continuationFormURL: continuationURL)
        let lookedUp = try XCTUnwrap(WAFormTemplateRepositoryImpl(defaults: defaults).currentTemplate())

        XCTAssertEqual(lookedUp.mainFormBookmark, imported.mainFormBookmark, "mainFormBookmark differs")
        XCTAssertEqual(
            lookedUp.continuationFormBookmark,
            imported.continuationFormBookmark,
            "continuationFormBookmark differs"
        )
        XCTAssertEqual(lookedUp.mainFormAccessMode, imported.mainFormAccessMode, "mainFormAccessMode differs")
        XCTAssertEqual(
            lookedUp.continuationFormAccessMode,
            imported.continuationFormAccessMode,
            "continuationFormAccessMode differs"
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

    func test_importTemplate_aSecondImport_replacesTheFirst() throws {
        let defaults = try makeDefaults()
        let repository = WAFormTemplateRepositoryImpl(defaults: defaults)
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
        XCTAssertEqual(current.mainFormBookmark, secondReference.mainFormBookmark)
        XCTAssertEqual(current.continuationFormBookmark, secondReference.continuationFormBookmark)
        XCTAssertEqual(current.mainFormFileName, secondMainURL.lastPathComponent)
        XCTAssertEqual(current.mainFormFileName, secondReference.mainFormFileName)
        XCTAssertEqual(current.continuationFormFileName, secondReference.continuationFormFileName)
        XCTAssertEqual(
            current.importedAt.timeIntervalSince1970,
            secondReference.importedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    /// Mirrors `AudioAnalysisRepositoryImpl`'s own confirmed behavior
    /// (`AudioAnalysisRepositoryImplTests`): an ordinary local test file,
    /// unsandboxed, successfully mints a real `.securityScoped` bookmark —
    /// the `.plainFallback` path is a real macOS-defect fallback (SPEC.md
    /// §4.10), not the expected outcome for an everyday file.
    func test_importTemplate_anOrdinaryLocalFile_mintsARealSecurityScopedBookmark() throws {
        let repository = try WAFormTemplateRepositoryImpl(defaults: makeDefaults())
        let reference = try repository.importTemplate(
            mainFormURL: temporaryPDFURL(),
            continuationFormURL: temporaryPDFURL()
        )
        XCTAssertEqual(reference.mainFormAccessMode, .securityScoped)
        XCTAssertEqual(reference.continuationFormAccessMode, .securityScoped)
    }

    func test_refreshBookmarkIfStale_aFreshlyMintedBookmark_returnsNil() throws {
        let repository = try WAFormTemplateRepositoryImpl(defaults: makeDefaults())
        let reference = try repository.importTemplate(
            mainFormURL: temporaryPDFURL(),
            continuationFormURL: temporaryPDFURL()
        )
        XCTAssertNil(try repository.refreshBookmarkIfStale(reference))
    }
}
