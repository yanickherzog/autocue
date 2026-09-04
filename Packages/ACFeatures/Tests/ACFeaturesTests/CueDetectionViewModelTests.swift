import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

@MainActor
final class CueDetectionViewModelTests: XCTestCase {
    private static func makeProject(audioAsset: AudioAsset?) -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            audioAsset: audioAsset,
            setup: Setup(
                title: "A Swiss Story",
                productionRuntime: .zero,
                totalMusicRuntime: .zero,
                productionYear: 2026,
                containsAdditionalUndeclaredWorks: .no,
                productionTypes: [.documentaryFilm],
                declarationDate: Date(timeIntervalSince1970: 0)
            )
        )
    }

    private func makeViewModel(
        project: Project,
        detectedCues: [Cue] = []
    ) -> (CueDetectionViewModel, InMemoryProjectRepository) {
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(detectedCues: detectedCues)
        let viewModel = CueDetectionViewModel(
            projectID: project.id,
            detectCuesUseCase: DetectCuesUseCase(
                audioAnalysisRepository: audioAnalysisRepository,
                projectRepository: projectRepository
            ),
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository)
        )
        return (viewModel, projectRepository)
    }

    func test_runDetectionIfNeeded_endsAtCompleted_andPersistsCues() async throws {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let project = Self.makeProject(audioAsset: asset)
        let detected = [
            Cue(
                title: "",
                duration: MediaDuration(seconds: 30),
                rightHolders: [],
                source: .detectedFromAudio,
                startTimecode: Timecode(offsetSeconds: 10)
            ),
        ]
        let (viewModel, projectRepository) = makeViewModel(project: project, detectedCues: detected)

        viewModel.runDetectionIfNeeded()

        try await waitUntil(timeout: 2.0) { viewModel.phase == .completed }

        let persisted = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(persisted?.cues.count, 1)
    }

    func test_runDetectionIfNeeded_calledTwice_onlyRunsOnce() async throws {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let project = Self.makeProject(audioAsset: asset)
        let (viewModel, _) = makeViewModel(project: project)

        viewModel.runDetectionIfNeeded()
        viewModel.runDetectionIfNeeded() // guarded no-op: phase is already non-.idle

        try await waitUntil(timeout: 2.0) { viewModel.phase == .completed }
    }

    func test_runDetectionIfNeeded_noAudioAsset_fails() async throws {
        let project = Self.makeProject(audioAsset: nil)
        let (viewModel, _) = makeViewModel(project: project)

        viewModel.runDetectionIfNeeded()

        try await waitUntil(timeout: 2.0) {
            if case .failed = viewModel.phase {
                return true
            }
            return false
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
