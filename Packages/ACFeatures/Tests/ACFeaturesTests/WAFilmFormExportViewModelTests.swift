import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `canExport`/`export` gating — mirrors `ExportViewModelTests`' own shape
/// for D11's analogous screen. See `WAFilmFormViewModelTests` for the
/// `load()`/template-import half; split purely to satisfy `SwiftLint`'s
/// `type_body_length` (`WAFilmFormTestFixtures`'s own doc comment).
@MainActor
final class WAFilmFormExportViewModelTests: XCTestCase {
    func test_canExport_noIssues_trueRegardlessOfStrictness() async throws {
        let project = WAFilmFormTestFixtures.makeProject()
        let viewModel = WAFilmFormTestFixtures.makeViewModel(
            project: project,
            templateRepository: InMemoryWAFormTemplateRepository(storedTemplate: WAFilmFormTestFixtures
                .makeReference()),
            shareValidationStrictness: .blockExport
        )
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.currentTemplate != nil }

        XCTAssertTrue(viewModel.canExport)
        loadTask.cancel()
    }

    func test_export_blockExportStrictness_withIssues_setsErrorMessage_neverSucceeds() async throws {
        let cueWithNoRightHolders = Cue(
            title: "Untitled",
            duration: MediaDuration(seconds: 30),
            rightHolders: [],
            source: .manual
        )
        let project = WAFilmFormTestFixtures.makeProject(cues: [cueWithNoRightHolders])
        let destination = URL(fileURLWithPath: "/tmp/wa-film.pdf")
        let viewModel = WAFilmFormTestFixtures.makeViewModel(
            project: project,
            templateRepository: InMemoryWAFormTemplateRepository(storedTemplate: WAFilmFormTestFixtures
                .makeReference()),
            exportRepository: InMemoryExportRepository(exportedURL: destination),
            shareValidationStrictness: .blockExport
        )
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.issues.isEmpty }

        await viewModel.export(to: destination)

        XCTAssertFalse(viewModel.lastExportSucceeded)
        XCTAssertNotNil(viewModel.exportErrorMessage)
        loadTask.cancel()
    }

    func test_export_warnOnlyStrictness_withIssues_stillSucceeds() async throws {
        let cueWithNoRightHolders = Cue(
            title: "Untitled",
            duration: MediaDuration(seconds: 30),
            rightHolders: [],
            source: .manual
        )
        let project = WAFilmFormTestFixtures.makeProject(cues: [cueWithNoRightHolders])
        let destination = URL(fileURLWithPath: "/tmp/wa-film.pdf")
        let viewModel = WAFilmFormTestFixtures.makeViewModel(
            project: project,
            templateRepository: InMemoryWAFormTemplateRepository(storedTemplate: WAFilmFormTestFixtures
                .makeReference()),
            exportRepository: InMemoryExportRepository(exportedURL: destination),
            shareValidationStrictness: .warnOnly
        )
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.issues.isEmpty }

        await viewModel.export(to: destination)

        XCTAssertTrue(viewModel.lastExportSucceeded)
        XCTAssertNil(viewModel.exportErrorMessage)
        loadTask.cancel()
    }

    func test_export_noTemplate_doesNothing() async {
        let project = WAFilmFormTestFixtures.makeProject()
        let viewModel = WAFilmFormTestFixtures.makeViewModel(project: project)

        await viewModel.export(to: URL(fileURLWithPath: "/tmp/wa-film.pdf"))

        XCTAssertFalse(viewModel.lastExportSucceeded)
        XCTAssertFalse(viewModel.isExporting)
    }

    func test_export_projectNotFound_setsExportErrorMessage() async {
        let missingProjectID = UUID()
        let projectRepository = InMemoryProjectRepository(projects: [])
        let templateRepository = InMemoryWAFormTemplateRepository(storedTemplate: WAFilmFormTestFixtures
            .makeReference())
        let viewModel = WAFilmFormViewModel(
            projectID: missingProjectID,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
            waFormTemplateUseCase: WAFormTemplateUseCase(waFormTemplateRepository: templateRepository),
            computeWAFormLayoutUseCase: ComputeWAFormLayoutUseCase(exportRepository: InMemoryExportRepository()),
            validateWAFormUseCase: ValidateWAFormUseCase(exportRepository: InMemoryExportRepository()),
            exportWAFormUseCase: ExportWAFormUseCase(
                projectRepository: projectRepository,
                exportRepository: InMemoryExportRepository()
            ),
            shareValidationStrictness: .warnOnly
        )
        // Imports the template directly without subscribing — `load()` would
        // otherwise never let `currentTemplate` get set, since this
        // `projectID` doesn't exist and `load()` breaks out immediately.
        await viewModel.importTemplate(
            mainFormURL: URL(fileURLWithPath: "/tmp/main.pdf"),
            continuationFormURL: URL(fileURLWithPath: "/tmp/continuation.pdf")
        )

        await viewModel.export(to: URL(fileURLWithPath: "/tmp/wa-film.pdf"))

        XCTAssertFalse(viewModel.lastExportSucceeded)
        XCTAssertNotNil(viewModel.exportErrorMessage)
    }
}
