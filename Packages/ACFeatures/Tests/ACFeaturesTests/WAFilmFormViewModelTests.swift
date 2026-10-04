import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `load()`/template-import behavior — see `WAFilmFormExportViewModelTests`
/// for the export/`canExport` gating half, split out purely to satisfy
/// `SwiftLint`'s `type_body_length` (`WAFilmFormTestFixtures`'s own doc
/// comment explains why).
@MainActor
final class WAFilmFormViewModelTests: XCTestCase {
    // MARK: - Template-less empty state

    func test_load_noTemplateImported_currentTemplateIsNil_noPreviewOrIssues() async throws {
        // A real cue (rather than `makeProject()`'s empty default) gives the
        // wait condition below a genuine, non-vacuous signal that `load()`'s
        // subscription has actually delivered its first emission — `cues`
        // starts `[]` and only becomes non-empty once that happens, unlike
        // `projectNotFound`, which already defaults to `false`.
        let project = WAFilmFormTestFixtures.makeProject(cues: [
            Cue(title: "Theme", duration: MediaDuration(seconds: 30), rightHolders: [], source: .manual),
        ])
        let viewModel = WAFilmFormTestFixtures.makeViewModel(project: project)

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.cues.isEmpty }

        XCTAssertNil(viewModel.currentTemplate)
        XCTAssertEqual(viewModel.previewPages, [])
        XCTAssertEqual(viewModel.issues, [])
        loadTask.cancel()
    }

    // MARK: - Template already stored at load time

    func test_load_templateAlreadyStored_populatesCurrentTemplateAndPreview() async throws {
        let project = WAFilmFormTestFixtures.makeProject()
        let reference = WAFilmFormTestFixtures.makeReference()
        let fakeLayout = [CueSheetPageLayout(pageIndex: 0, pageCount: 1, elements: [])]
        let viewModel = WAFilmFormTestFixtures.makeViewModel(
            project: project,
            templateRepository: InMemoryWAFormTemplateRepository(storedTemplate: reference),
            exportRepository: InMemoryExportRepository(waFormLayoutToReturn: fakeLayout)
        )

        let loadTask = Task { await viewModel.load() }
        // Waits on `previewPages`, not `currentTemplate` — `loadTemplate()`
        // sets `currentTemplate` synchronously before `load()`'s
        // subscription loop even starts, so that condition would be
        // satisfied before `recomputePreviewAndValidation` has actually run
        // (a genuine race, not a vacuous initial-value one like
        // `projectNotFound`'s — caught by this same test failing before this
        // fix).
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.previewPages.isEmpty }

        XCTAssertEqual(viewModel.currentTemplate, reference)
        XCTAssertEqual(viewModel.previewPages, fakeLayout)
        XCTAssertNil(viewModel.templateAccessErrorMessage)
        loadTask.cancel()
    }

    func test_load_templateAlreadyStored_populatesTemplateFileURLs() async throws {
        let project = WAFilmFormTestFixtures.makeProject()
        let reference = WAFilmFormTestFixtures.makeReference()
        let viewModel = WAFilmFormTestFixtures.makeViewModel(
            project: project,
            templateRepository: InMemoryWAFormTemplateRepository(storedTemplate: reference)
        )

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.currentTemplate != nil }

        XCTAssertNotNil(viewModel.templateFileURLs)
        loadTask.cancel()
    }

    /// A real file-I/O failure resolving the stored template's live
    /// continuation page count (`ExportRepository.continuationTemplatePageCount`)
    /// surfaces as `templateAccessErrorMessage`, not a silent empty preview.
    func test_load_templateAccessFails_setsTemplateAccessErrorMessage() async throws {
        enum TestError: Error { case boom }
        let project = WAFilmFormTestFixtures.makeProject()
        let reference = WAFilmFormTestFixtures.makeReference()
        let viewModel = WAFilmFormTestFixtures.makeViewModel(
            project: project,
            templateRepository: InMemoryWAFormTemplateRepository(storedTemplate: reference),
            exportRepository: InMemoryExportRepository(waFormLayoutError: TestError.boom)
        )

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.templateAccessErrorMessage != nil }

        XCTAssertEqual(viewModel.previewPages, [])
        XCTAssertEqual(viewModel.issues, [])
        loadTask.cancel()
    }

    // MARK: - importTemplate

    func test_importTemplate_success_updatesCurrentTemplateAndRecomputesPreview() async throws {
        // A real cue gives the wait condition below a genuine signal that
        // `load()`'s subscription has delivered its first emission (and
        // therefore that `latestProject` is actually set) — see the
        // identical reasoning in `test_load_noTemplateImported_...` above.
        let project = WAFilmFormTestFixtures.makeProject(cues: [
            Cue(title: "Theme", duration: MediaDuration(seconds: 30), rightHolders: [], source: .manual),
        ])
        let fakeLayout = [CueSheetPageLayout(pageIndex: 0, pageCount: 1, elements: [])]
        let viewModel = WAFilmFormTestFixtures.makeViewModel(
            project: project,
            exportRepository: InMemoryExportRepository(waFormLayoutToReturn: fakeLayout)
        )

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.cues.isEmpty }

        await viewModel.importTemplate(
            mainFormURL: URL(fileURLWithPath: "/tmp/main.pdf"),
            continuationFormURL: URL(fileURLWithPath: "/tmp/continuation.pdf")
        )

        XCTAssertNotNil(viewModel.currentTemplate)
        XCTAssertEqual(viewModel.currentTemplate?.mainFormFileName, "main.pdf")
        XCTAssertEqual(viewModel.previewPages, fakeLayout)
        XCTAssertNil(viewModel.importErrorMessage)
        loadTask.cancel()
    }

    func test_importTemplate_failure_setsImportErrorMessage_currentTemplateStaysNil() async {
        enum TestError: Error { case boom }
        let project = WAFilmFormTestFixtures.makeProject()
        let viewModel = WAFilmFormTestFixtures.makeViewModel(
            project: project,
            templateRepository: InMemoryWAFormTemplateRepository(importError: TestError.boom)
        )

        await viewModel.importTemplate(
            mainFormURL: URL(fileURLWithPath: "/tmp/main.pdf"),
            continuationFormURL: URL(fileURLWithPath: "/tmp/continuation.pdf")
        )

        XCTAssertNil(viewModel.currentTemplate)
        XCTAssertNotNil(viewModel.importErrorMessage)
    }

    // MARK: - projectNotFound

    func test_load_projectNotFound_setsFlag() async {
        let missingProjectID = UUID()
        let projectRepository = InMemoryProjectRepository(projects: [])
        let viewModel = WAFilmFormViewModel(
            projectID: missingProjectID,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
            waFormTemplateUseCase: WAFormTemplateUseCase(
                waFormTemplateRepository: InMemoryWAFormTemplateRepository()
            ),
            computeWAFormLayoutUseCase: ComputeWAFormLayoutUseCase(exportRepository: InMemoryExportRepository()),
            validateWAFormUseCase: ValidateWAFormUseCase(exportRepository: InMemoryExportRepository()),
            exportWAFormUseCase: ExportWAFormUseCase(
                projectRepository: projectRepository,
                exportRepository: InMemoryExportRepository()
            ),
            shareValidationStrictness: .warnOnly
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.projectNotFound)
    }
}
