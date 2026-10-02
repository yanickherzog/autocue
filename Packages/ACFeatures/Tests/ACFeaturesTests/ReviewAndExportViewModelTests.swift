import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// Confirms `ReviewAndExportViewModel` is exactly the thin composition its
/// own doc comment claims — all three child ViewModels share the same
/// `projectID` and are independently functional, wired through the same
/// fakes `ReviewViewModelTests`/`ExportViewModelTests` already establish.
@MainActor
final class ReviewAndExportViewModelTests: XCTestCase {
    func test_composesAllThreeChildViewModels_sharingTheSameProjectID() {
        let project = ProjectFixture.makeMinimal()
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let exportRepository = InMemoryExportRepository()

        let reviewViewModel = ReviewViewModel(
            projectID: project.id,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository)
        )
        let cueSheetPreviewViewModel = CueSheetPreviewViewModel(
            projectID: project.id,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
            computeCueSheetLayoutUseCase: ComputeCueSheetLayoutUseCase(exportRepository: exportRepository)
        )
        let exportViewModel = ExportViewModel(
            projectID: project.id,
            exportCueSheetUseCase: ExportCueSheetUseCase(
                projectRepository: projectRepository,
                exportRepository: exportRepository
            ),
            shareValidationStrictness: .warnOnly
        )

        let viewModel = ReviewAndExportViewModel(
            reviewViewModel: reviewViewModel,
            cueSheetPreviewViewModel: cueSheetPreviewViewModel,
            exportViewModel: exportViewModel
        )

        XCTAssertEqual(viewModel.reviewViewModel.projectID, project.id)
        XCTAssertEqual(viewModel.cueSheetPreviewViewModel.projectID, project.id)
        XCTAssertEqual(viewModel.exportViewModel.projectID, project.id)
    }
}
