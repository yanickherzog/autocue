import ACCore
@testable import ACExport
import ACTestSupport
import CoreGraphics
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

    // MARK: - WA Film form (ROADMAP.md D12)

    private func makeTemplate(mainPageCount: Int, continuationPageCount: Int) throws -> WAFormTemplateReference {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ExportRepositoryImplTests-\(UUID().uuidString)"))
        let templateRepository = WAFormTemplateRepositoryImpl(defaults: defaults)
        let mainURL = try makeSyntheticTemplatePDF(pageCount: mainPageCount)
        let continuationURL = try makeSyntheticTemplatePDF(pageCount: continuationPageCount)
        return try templateRepository.importTemplate(mainFormURL: mainURL, continuationFormURL: continuationURL)
    }

    private func makeSyntheticTemplatePDF(pageCount: Int) throws -> URL {
        let url = temporaryURL(extension: "pdf")
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw XCTSkip("Could not create data consumer")
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 595.7, height: 841.227)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw XCTSkip("Could not create PDF context")
        }
        for _ in 0 ..< max(pageCount, 1) {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    func test_computeWAFormLayout_readsTheRealContinuationTemplatesPageCount_notAHardcodedNumber() throws {
        let repository = ExportRepositoryImpl()
        let template = try makeTemplate(mainPageCount: 2, continuationPageCount: 2)

        let cues = (0 ..< 13).map { index in
            Cue(
                title: "Cue \(index)",
                duration: MediaDuration(seconds: 30),
                rightHolders: [
                    CueRightHolder(
                        party: .person(UUID()),
                        role: .composer,
                        performanceBroadcastShare: 100,
                        mechanicalRightsShare: 100
                    ),
                ],
                source: .manual
            )
        }
        var project = ProjectFixture.makeMinimal()
        project = Project(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            setup: project.setup,
            cues: cues
        )

        // 13 cues need 2 continuation pages (8 remaining after the main
        // form's 5, 4 per page) — the real template only has 2, so this
        // must cap there, not assume a larger/hardcoded capacity.
        let pages = try repository.computeWAFormLayout(for: project, template: template)
        XCTAssertEqual(pages.count, 4)
    }

    func test_exportWAForm_producesARealFileAndCompletes() async throws {
        let repository = ExportRepositoryImpl()
        let template = try makeTemplate(mainPageCount: 2, continuationPageCount: 1)
        let outputURL = temporaryURL(extension: "pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var completedURL: URL?
        for try await event in repository.exportWAForm(
            project: ProjectFixture.make(),
            template: template,
            to: outputURL
        ) {
            if case let .completed(resultURL) = event {
                completedURL = resultURL
            }
        }

        XCTAssertEqual(completedURL, outputURL)
        let data = try Data(contentsOf: outputURL)
        let header = try XCTUnwrap(String(bytes: data.prefix(5), encoding: .utf8))
        XCTAssertEqual(header, "%PDF-")
    }
}
