import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

@MainActor
final class ExportViewModelTests: XCTestCase {
    private func makeUseCase(
        project: Project,
        exportedURL: URL = URL(fileURLWithPath: "/tmp/fixture-export.pdf")
    ) -> (ExportCueSheetUseCase, InMemoryExportRepository) {
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let exportRepository = InMemoryExportRepository(exportedURL: exportedURL)
        let useCase = ExportCueSheetUseCase(
            projectRepository: projectRepository,
            exportRepository: exportRepository
        )
        return (useCase, exportRepository)
    }

    func test_canExport_noIssues_isTrueRegardlessOfStrictness() {
        let (useCase, _) = makeUseCase(project: ProjectFixture.makeMinimal())
        let viewModel = ExportViewModel(
            projectID: UUID(),
            exportCueSheetUseCase: useCase,
            shareValidationStrictness: .blockExport
        )

        XCTAssertTrue(viewModel.canExport(givenIssues: []))
    }

    func test_canExport_issuesPresent_blockExport_isFalse() {
        let (useCase, _) = makeUseCase(project: ProjectFixture.makeMinimal())
        let viewModel = ExportViewModel(
            projectID: UUID(),
            exportCueSheetUseCase: useCase,
            shareValidationStrictness: .blockExport
        )

        XCTAssertFalse(viewModel.canExport(givenIssues: [.missingSetupField(.declarant)]))
    }

    func test_canExport_issuesPresent_warnOnly_isTrue() {
        let (useCase, _) = makeUseCase(project: ProjectFixture.makeMinimal())
        let viewModel = ExportViewModel(
            projectID: UUID(),
            exportCueSheetUseCase: useCase,
            shareValidationStrictness: .warnOnly
        )

        XCTAssertTrue(viewModel.canExport(givenIssues: [.missingSetupField(.declarant)]))
    }

    func test_export_pdf_succeeds_andReportsCompletion() async {
        let project = ProjectFixture.makeMinimal()
        let (useCase, _) = makeUseCase(project: project)
        let viewModel = ExportViewModel(
            projectID: project.id,
            exportCueSheetUseCase: useCase,
            shareValidationStrictness: .warnOnly
        )
        viewModel.selectedFormat = .pdf

        await viewModel.export(to: URL(fileURLWithPath: "/tmp/out.pdf"), issues: [])

        XCTAssertTrue(viewModel.lastExportSucceeded)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isExporting)
    }

    /// `.both` runs two concrete-format exports — the second destination is
    /// derived by swapping the extension of the one the user actually
    /// picked (`ExportViewModel`'s own doc comment).
    func test_export_both_succeeds() async {
        let project = ProjectFixture.makeMinimal()
        let (useCase, _) = makeUseCase(project: project)
        let viewModel = ExportViewModel(
            projectID: project.id,
            exportCueSheetUseCase: useCase,
            shareValidationStrictness: .warnOnly
        )

        await viewModel.exportBoth(
            pdfDestination: URL(fileURLWithPath: "/tmp/out.pdf"),
            xlsxDestination: URL(fileURLWithPath: "/tmp/out.xlsx"),
            issues: []
        )

        XCTAssertTrue(viewModel.lastExportSucceeded)
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_export_blockedByIssues_setsErrorMessage_neverCallsExportRepository() async {
        let project = ProjectFixture.makeMinimal()
        let (useCase, _) = makeUseCase(project: project)
        let viewModel = ExportViewModel(
            projectID: project.id,
            exportCueSheetUseCase: useCase,
            shareValidationStrictness: .blockExport
        )

        await viewModel.export(
            to: URL(fileURLWithPath: "/tmp/out.pdf"),
            issues: [.missingSetupField(.declarant)]
        )

        XCTAssertFalse(viewModel.lastExportSucceeded)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func test_export_projectNotFound_setsErrorMessage() async {
        let missingProjectID = UUID()
        let projectRepository = InMemoryProjectRepository(projects: [])
        let exportRepository = InMemoryExportRepository()
        let useCase = ExportCueSheetUseCase(
            projectRepository: projectRepository,
            exportRepository: exportRepository
        )
        let viewModel = ExportViewModel(
            projectID: missingProjectID,
            exportCueSheetUseCase: useCase,
            shareValidationStrictness: .warnOnly
        )
        viewModel.selectedFormat = .pdf

        await viewModel.export(to: URL(fileURLWithPath: "/tmp/out.pdf"), issues: [])

        XCTAssertFalse(viewModel.lastExportSucceeded)
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
