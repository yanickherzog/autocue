import ACCore
@testable import ACExport
import ACTestSupport
import XCTest

final class ExportRepositoryImplTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
    }

    func test_computeLayout_delegatesToCueSheetLayoutComputer() {
        let repository = ExportRepositoryImpl()
        let project = ProjectFixture.make()
        XCTAssertEqual(repository.computeLayout(for: project), CueSheetLayoutComputer.computeLayout(for: project))
    }

    func test_export_pdf_producesARealFileAndCompletes() async throws {
        let repository = ExportRepositoryImpl()
        let url = temporaryURL()
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

    func test_export_xlsx_throwsFormatNotYetImplemented() async {
        let repository = ExportRepositoryImpl()
        do {
            for try await _ in repository.export(project: ProjectFixture.make(), format: .xlsx, to: temporaryURL()) {}
            XCTFail("Expected formatNotYetImplemented to be thrown")
        } catch ExportRepositoryImpl.ExportError.formatNotYetImplemented(.xlsx) {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_export_both_throwsFormatNotYetImplemented() async {
        let repository = ExportRepositoryImpl()
        do {
            for try await _ in repository.export(project: ProjectFixture.make(), format: .both, to: temporaryURL()) {}
            XCTFail("Expected formatNotYetImplemented to be thrown")
        } catch ExportRepositoryImpl.ExportError.formatNotYetImplemented(.both) {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
