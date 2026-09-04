import ACCore
import ACDesignSystem
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

@MainActor
final class CueDetectionReviewViewModelTests: XCTestCase {
    private static func makeCue(startSeconds: Double, duration: Double, source: CueSource = .detectedFromAudio) -> Cue {
        Cue(
            title: "",
            duration: MediaDuration(seconds: duration),
            rightHolders: [],
            source: source,
            startTimecode: Timecode(offsetSeconds: startSeconds)
        )
    }

    private static func makeProject(cues: [Cue], audioAsset: AudioAsset, waveformPeaks: WaveformPeaks?) -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            audioAsset: audioAsset,
            waveformPeaks: waveformPeaks,
            setup: Setup(
                title: "A Swiss Story",
                productionRuntime: .zero,
                totalMusicRuntime: .zero,
                productionYear: 2026,
                containsAdditionalUndeclaredWorks: .no,
                productionTypes: [.documentaryFilm],
                declarationDate: Date(timeIntervalSince1970: 0)
            ),
            cues: cues
        )
    }

    private struct TestEnvironment {
        let viewModel: CueDetectionReviewViewModel
        let projectRepository: InMemoryProjectRepository
        let playbackController: InMemoryAudioPlaybackController
        let project: Project
    }

    private func makeEnvironment(cues: [Cue]) -> TestEnvironment {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let peaks = WaveformPeaks(
            audioAssetID: asset.id,
            resolution: 4,
            buckets: (0 ..< 4).map { _ in WaveformPeakBucket(min: -0.5, max: 0.5) }
        )
        let project = Self.makeProject(cues: cues, audioAsset: asset, waveformPeaks: peaks)
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(importedAsset: asset)
        let playbackController = InMemoryAudioPlaybackController()
        let viewModel = CueDetectionReviewViewModel(
            projectID: project.id,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
            generateWaveformDetailUseCase: GenerateWaveformDetailUseCase(
                audioAnalysisRepository: audioAnalysisRepository,
                projectRepository: projectRepository
            ),
            updateCueUseCase: UpdateCueUseCase(projectRepository: projectRepository),
            audioPlaybackController: playbackController
        )
        return TestEnvironment(
            viewModel: viewModel,
            projectRepository: projectRepository,
            playbackController: playbackController,
            project: project
        )
    }

    func test_load_populatesCuesAndMarkersAndDisplayData() async throws {
        let cue = Self.makeCue(startSeconds: 10, duration: 30)
        let env = makeEnvironment(cues: [cue])
        let viewModel = env.viewModel

        let loadTask = Task { await viewModel.load() }
        try await waitUntil { viewModel.cues.count == 1 }
        loadTask.cancel()

        XCTAssertEqual(viewModel.markers.count, 1)
        XCTAssertEqual(viewModel.markers.first?.offsetSeconds, 10)
        XCTAssertFalse(viewModel.displayData.buckets.isEmpty)
        XCTAssertEqual(viewModel.visibleRangeSeconds, 0 ... viewModel.fileDurationSeconds)
    }

    func test_cuesWithNoStartTimecode_areExcludedFromMarkers() async throws {
        let cueWithPosition = Self.makeCue(startSeconds: 10, duration: 30)
        let cueWithoutPosition = Cue(title: "Manual", duration: .zero, rightHolders: [], source: .manual)
        let env = makeEnvironment(cues: [cueWithPosition, cueWithoutPosition])
        let viewModel = env.viewModel

        let loadTask = Task { await viewModel.load() }
        try await waitUntil { viewModel.cues.count == 2 }
        loadTask.cancel()

        XCTAssertEqual(viewModel.markers.count, 1)
        XCTAssertEqual(viewModel.markers.first?.id, 0)
    }

    func test_boundaryDragged_writesThroughAndReclassifiesToManual() async throws {
        let cue = Self.makeCue(startSeconds: 10, duration: 30, source: .detectedFromAudio)
        let env = makeEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntil { viewModel.cues.count == 1 }

        viewModel.boundaryDragged(markerID: 0, toSeconds: 15)

        try await waitUntil {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first?.startTimecode == Timecode(offsetSeconds: 15)
        }
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.first?.source, .manual)
        // TC Out (end) stays fixed at the original 40 — only the start moved.
        XCTAssertEqual(try XCTUnwrap(updated?.cues.first?.duration.seconds), 25, accuracy: 0.0001)
        loadTask.cancel()
    }

    func test_splitRequested_insideACueRegion_splitsIt() async throws {
        let cue = Self.makeCue(startSeconds: 10, duration: 30)
        let env = makeEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntil { viewModel.cues.count == 1 }

        viewModel.splitRequested(atSeconds: 25)

        try await waitUntil {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 2
        }
        loadTask.cancel()
    }

    func test_splitRequested_outsideAnyCueRegion_isANoOp() async throws {
        let cue = Self.makeCue(startSeconds: 10, duration: 30)
        let env = makeEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntil { viewModel.cues.count == 1 }

        viewModel.splitRequested(atSeconds: 5) // before the cue's own start

        try await Task.sleep(nanoseconds: 50_000_000)
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.count, 1)
        loadTask.cancel()
    }

    func test_mergeRequested_eligiblePair_merges() async throws {
        let preceding = Self.makeCue(startSeconds: 10, duration: 30) // [10, 40)
        let following = Self.makeCue(startSeconds: 40, duration: 20) // [40, 60)
        let env = makeEnvironment(cues: [preceding, following])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntil { viewModel.cues.count == 2 }

        viewModel.mergeRequested(markerID: 1)

        try await waitUntil {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 1
        }
        loadTask.cancel()
    }

    func test_mergeRequested_firstCue_isANoOp() async throws {
        let cue = Self.makeCue(startSeconds: 10, duration: 30)
        let env = makeEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntil { viewModel.cues.count == 1 }

        viewModel.mergeRequested(markerID: 0) // no preceding neighbor

        try await Task.sleep(nanoseconds: 50_000_000)
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.count, 1)
        loadTask.cancel()
    }

    func test_playFromPoint_callsPlaybackController() async throws {
        let env = makeEnvironment(cues: [])
        let viewModel = env.viewModel
        let playbackController = env.playbackController
        let loadTask = Task { await viewModel.load() }
        try await waitUntil { await playbackController.prepareCallCount == 1 }

        viewModel.playFromPoint(atSeconds: 12.5)

        try await waitUntil { await !(playbackController.playCalls.isEmpty) }
        let calls = await playbackController.playCalls
        XCTAssertEqual(calls.first?.from, 12.5)
        XCTAssertNil(calls.first?.until)
        loadTask.cancel()
    }

    func test_playMarkerSpan_playsExactCueSpan() async throws {
        let cue = Self.makeCue(startSeconds: 10, duration: 30)
        let env = makeEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let playbackController = env.playbackController
        let loadTask = Task { await viewModel.load() }
        try await waitUntil { viewModel.cues.count == 1 }

        viewModel.playMarkerSpan(markerID: 0)

        try await waitUntil { await !(playbackController.playCalls.isEmpty) }
        let calls = await playbackController.playCalls
        XCTAssertEqual(calls.first?.from, 10)
        XCTAssertEqual(calls.first?.until, 40)
        loadTask.cancel()
    }

    func test_playbackFailure_setsADistinguishingErrorMessage_notAGenericOne() async throws {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let peaks = WaveformPeaks(audioAssetID: asset.id, resolution: 4, buckets: [])
        let project = Self.makeProject(cues: [], audioAsset: asset, waveformPeaks: peaks)
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let playbackController = InMemoryAudioPlaybackController(prepareError: URLError(.fileDoesNotExist))
        let viewModel = CueDetectionReviewViewModel(
            projectID: project.id,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
            generateWaveformDetailUseCase: GenerateWaveformDetailUseCase(
                audioAnalysisRepository: InMemoryAudioAnalysisRepository(importedAsset: asset),
                projectRepository: projectRepository
            ),
            updateCueUseCase: UpdateCueUseCase(projectRepository: projectRepository),
            audioPlaybackController: playbackController
        )

        let loadTask = Task { await viewModel.load() }
        try await waitUntil { viewModel.errorMessage != nil }

        XCTAssertEqual(
            viewModel.errorMessage,
            "This file's audio could no longer be located. Re-import it to restore waveform and playback access."
        )
        loadTask.cancel()
    }

    private func waitUntil(
        timeout: TimeInterval = 2.0,
        condition: @escaping () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while try await !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
