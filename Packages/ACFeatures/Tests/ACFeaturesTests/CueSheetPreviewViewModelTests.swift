import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

@MainActor
final class CueSheetPreviewViewModelTests: XCTestCase {
    private func makeViewModel(
        project: Project,
        projectRepository: InMemoryProjectRepository,
        layoutToReturn: [CueSheetPageLayout]
    ) -> CueSheetPreviewViewModel {
        CueSheetPreviewViewModel(
            projectID: project.id,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
            computeCueSheetLayoutUseCase: ComputeCueSheetLayoutUseCase(
                exportRepository: InMemoryExportRepository(layoutToReturn: layoutToReturn)
            )
        )
    }

    func test_load_populatesPagesFromTheComputeUseCase() async throws {
        let project = ProjectFixture.make()
        let repository = InMemoryProjectRepository(projects: [project])
        let expectedPages = [CueSheetPageLayout(pageIndex: 0, pageCount: 1, elements: [])]
        let viewModel = makeViewModel(project: project, projectRepository: repository, layoutToReturn: expectedPages)

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.pages.isEmpty }

        XCTAssertEqual(viewModel.pages, expectedPages)
        XCTAssertFalse(viewModel.projectNotFound)
        loadTask.cancel()
    }

    func test_load_projectDoesNotExist_setsProjectNotFound() async {
        let repository = InMemoryProjectRepository(projects: [])
        let viewModel = CueSheetPreviewViewModel(
            projectID: UUID(),
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: repository),
            computeCueSheetLayoutUseCase: ComputeCueSheetLayoutUseCase(exportRepository: InMemoryExportRepository())
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.projectNotFound)
        XCTAssertEqual(viewModel.pages, [])
    }
}
