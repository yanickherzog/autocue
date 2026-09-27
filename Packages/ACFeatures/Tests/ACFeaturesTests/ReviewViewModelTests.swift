import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

@MainActor
final class ReviewViewModelTests: XCTestCase {
    private func makeValidSetup() -> Setup {
        Setup(
            title: "A Swiss Story",
            producer: [.person(UUID())],
            directorOrPrincipal: [.person(UUID())],
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: MediaDuration(seconds: 620),
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.documentaryFilm],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeValidCue(id: Cue.ID = UUID()) -> Cue {
        Cue(
            id: id,
            title: "Opening Theme",
            duration: MediaDuration(seconds: 60),
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

    private func makeProject(setup: Setup, cues: [Cue] = []) -> Project {
        Project(name: "Reel One", createdAt: Date(), updatedAt: Date(), setup: setup, cues: cues)
    }

    private func makeViewModel(project: Project, repository: InMemoryProjectRepository) -> ReviewViewModel {
        ReviewViewModel(
            projectID: project.id,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: repository)
        )
    }

    func test_load_fullyValidProject_populatesEmptyIssuesAndTotalMusicRuntime() async throws {
        let project = makeProject(setup: makeValidSetup(), cues: [makeValidCue()])
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.cues.isEmpty }

        XCTAssertEqual(viewModel.issues, [])
        XCTAssertEqual(viewModel.totalMusicRuntime, MediaDuration(seconds: 620))
        XCTAssertFalse(viewModel.projectNotFound)
        loadTask.cancel()
    }

    func test_load_missingDeclarant_reportsTheIssue() async throws {
        let setup = Setup(
            title: "A Swiss Story",
            producer: [.person(UUID())],
            directorOrPrincipal: [.person(UUID())],
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.documentaryFilm],
            declarationDate: Date(timeIntervalSince1970: 0)
        )
        let project = makeProject(setup: setup)
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.issues.isEmpty }

        XCTAssertEqual(viewModel.issues, [.missingSetupField(.declarant)])
        loadTask.cancel()
    }

    func test_load_projectDoesNotExist_setsProjectNotFound() async {
        let repository = InMemoryProjectRepository(projects: [])
        let viewModel = ReviewViewModel(
            projectID: UUID(),
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: repository)
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.projectNotFound)
        XCTAssertEqual(viewModel.issues, [])
    }

    /// The concrete verification `ROADMAP.md` D11's own Acceptance Criteria
    /// names explicitly: constructs `CueDetectionReviewViewModel` and
    /// `ReviewViewModel` against the same fake `ProjectRepository`, both
    /// subscribed to its live-observation stream; deletes a cue via
    /// `CueDetectionReviewViewModel`; asserts `ReviewViewModel`'s observed
    /// validation state updates to reflect the deletion — awaiting the
    /// stream's next emission, never calling an explicit refresh method on
    /// either ViewModel. Tracks the specific `.cueHasNoRightHolders` issue
    /// rather than overall emptiness, since the shared
    /// `makeCueDetectionReviewEnvironment` fixture's `Setup` has its own,
    /// unrelated, permanently-missing required fields — this test isolates
    /// exactly the propagation behavior being verified, not Setup
    /// completeness.
    func test_cueDeletedViaCueDetectionReviewViewModel_propagatesLiveToReviewViewModel_noManualRefresh() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let deletedCueID = cue.id
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let cueDetectionViewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let reviewViewModel = ReviewViewModel(
            projectID: project.id,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository)
        )

        let cueDetectionLoadTask = Task { await cueDetectionViewModel.load() }
        let reviewLoadTask = Task { await reviewViewModel.load() }

        try await waitUntilCueDetectionReviewConditionMet { cueDetectionViewModel.cues.count == 1 }
        try await waitUntilCueDetectionReviewConditionMet {
            reviewViewModel.issues.contains(.cueHasNoRightHolders(cueID: deletedCueID))
        }

        cueDetectionViewModel.deleteCue(at: 0, undoManager: nil)

        try await waitUntilCueDetectionReviewConditionMet {
            !reviewViewModel.issues.contains(.cueHasNoRightHolders(cueID: deletedCueID))
        }

        cueDetectionLoadTask.cancel()
        reviewLoadTask.cancel()
    }
}
