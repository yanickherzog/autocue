import ACCore
@testable import ACExport
import ACTestSupport
import XCTest

final class ExportRepositoryImplTests: XCTestCase {
    private func temporaryURL(extension pathExtension: String = "pdf") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
    }

    func test_computeLayout_delegatesToCueSheetLayoutComputer() {
        let repository = ExportRepositoryImpl()
        let project = ProjectFixture.make()
        XCTAssertEqual(repository.computeLayout(for: project), CueSheetLayoutComputer.computeLayout(for: project))
    }

    func test_export_pdf_producesARealFileAndCompletes() async throws {
        let repository = ExportRepositoryImpl()
        let url = temporaryURL(extension: "pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        var completedURL: URL?
        for try await event in repository.export(project: ProjectFixture.make(), format: .pdf, to: url) {
            if case let .completed(resultURL) = event {
                completedURL = resultURL
            }
        }

        XCTAssertEqual(completedURL, url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// Real XLSX generation through the actual `ExportRepository` entry
    /// point, not just `XLSXCueSheetWriter` directly — proves the wiring
    /// itself, not only the writer in isolation.
    func test_export_xlsx_producesARealFileAndCompletes() async throws {
        let repository = ExportRepositoryImpl()
        let url = temporaryURL(extension: "xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        var completedURL: URL?
        for try await event in repository.export(project: ProjectFixture.make(), format: .xlsx, to: url) {
            if case let .completed(resultURL) = event {
                completedURL = resultURL
            }
        }

        XCTAssertEqual(completedURL, url)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "missing ZIP local file header signature")
    }

    /// `.both` is deliberately rejected here — splitting it into two
    /// concrete-format calls is `ExportViewModel`'s job (`ROADMAP.md`
    /// D11/T11.5, see this type's own doc comment for why).
    func test_export_both_isRejected() async {
        let repository = ExportRepositoryImpl()
        do {
            for try await _ in repository.export(project: ProjectFixture.make(), format: .both, to: temporaryURL()) {}
            XCTFail("Expected bothIsNotASingleExportOperation to be thrown")
        } catch ExportRepositoryImpl.ExportError.bothIsNotASingleExportOperation {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// An ordinary (non-security-scoped) file URL, like this test's own
    /// temporary directory, is exactly what real usage after a
    /// `.fileExporter` grant is not — but confirms
    /// `startAccessingSecurityScopedResource()`'s well-documented no-op
    /// behavior for a plain URL doesn't break the ordinary case, rather than
    /// only being exercised implicitly by the tests above.
    func test_export_pdf_stillSucceeds_whenDestinationIsNotSecurityScoped() async throws {
        let repository = ExportRepositoryImpl()
        let url = temporaryURL(extension: "pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        for try await _ in repository.export(project: ProjectFixture.make(), format: .pdf, to: url) {}

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
