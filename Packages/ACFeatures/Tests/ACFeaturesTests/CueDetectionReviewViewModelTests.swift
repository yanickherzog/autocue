import ACCore
import ACDesignSystem
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

@MainActor
final class CueDetectionReviewViewModelTests: XCTestCase {
    func test_load_populatesCuesAndMarkersAndDisplayData() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }
        loadTask.cancel()

        XCTAssertEqual(viewModel.markers.count, 1)
        XCTAssertEqual(viewModel.markers.first?.offsetSeconds, 10)
        XCTAssertFalse(viewModel.displayData.buckets.isEmpty)
        XCTAssertEqual(viewModel.visibleRangeSeconds, 0 ... viewModel.fileDurationSeconds)
    }

    func test_cuesWithNoStartTimecode_areExcludedFromMarkers() async throws {
        let cueWithPosition = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let cueWithoutPosition = Cue(title: "Manual", duration: .zero, rightHolders: [], source: .manual)
        let env = makeCueDetectionReviewEnvironment(cues: [cueWithPosition, cueWithoutPosition])
        let viewModel = env.viewModel

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }
        loadTask.cancel()

        XCTAssertEqual(viewModel.markers.count, 1)
        XCTAssertEqual(viewModel.markers.first?.id, 0)
    }

    func test_boundaryDragged_writesThroughAndReclassifiesToManual() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30, source: .detectedFromAudio)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.boundaryDragged(markerID: 0, toSeconds: 15)

        try await waitUntilCueDetectionReviewConditionMet {
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
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.splitRequested(atSeconds: 25)

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 2
        }
        loadTask.cancel()
    }

    func test_splitRequested_outsideAnyCueRegion_isANoOp() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.splitRequested(atSeconds: 5) // before the cue's own start

        try await Task.sleep(nanoseconds: 50_000_000)
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.count, 1)
        loadTask.cancel()
    }

    func test_mergeRequested_eligiblePair_merges() async throws {
        let preceding = makeCueDetectionReviewCue(startSeconds: 10, duration: 30) // [10, 40)
        let following = makeCueDetectionReviewCue(startSeconds: 40, duration: 20) // [40, 60)
        let env = makeCueDetectionReviewEnvironment(cues: [preceding, following])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.mergeRequested(markerID: 1)

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 1
        }
        loadTask.cancel()
    }

    func test_mergeRequested_firstCue_isANoOp() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.mergeRequested(markerID: 0) // no preceding neighbor

        try await Task.sleep(nanoseconds: 50_000_000)
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.count, 1)
        loadTask.cancel()
    }

    func test_playFromPoint_callsPlaybackController() async throws {
        let env = makeCueDetectionReviewEnvironment(cues: [])
        let viewModel = env.viewModel
        let playbackController = env.playbackController
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { await playbackController.prepareCallCount == 1 }

        viewModel.playFromPoint(atSeconds: 12.5)

        try await waitUntilCueDetectionReviewConditionMet { await !(playbackController.playCalls.isEmpty) }
        let calls = await playbackController.playCalls
        XCTAssertEqual(calls.first?.from, 12.5)
        XCTAssertNil(calls.first?.until)
        loadTask.cancel()
    }

    func test_playMarkerSpan_playsExactCueSpan() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let playbackController = env.playbackController
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.playMarkerSpan(markerID: 0)

        try await waitUntilCueDetectionReviewConditionMet { await !(playbackController.playCalls.isEmpty) }
        let calls = await playbackController.playCalls
        XCTAssertEqual(calls.first?.from, 10)
        XCTAssertEqual(calls.first?.until, 40)
        loadTask.cancel()
    }

    // MARK: - Clear imported audio

    func test_clearImportedAudio_removesAssetPeaksAndCues_andStopsPlaybackFirst() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let playbackController = env.playbackController
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.clearImportedAudio()

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.audioAsset == nil
        }
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertNil(updated?.audioAsset)
        XCTAssertNil(updated?.waveformPeaks)
        XCTAssertEqual(updated?.cues, [])
        let stopCallCount = await playbackController.stopCallCount
        XCTAssertEqual(stopCallCount, 1, "playback must be stopped before the audio it depends on is cleared")
        loadTask.cancel()
    }

    func test_playbackFailure_setsADistinguishingErrorMessage_notAGenericOne() async throws {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let peaks = WaveformPeaks(audioAssetID: asset.id, resolution: 4, buckets: [])
        let project = makeCueDetectionReviewProject(cues: [], audioAsset: asset, waveformPeaks: peaks)
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
            clearImportedAudioUseCase: ClearImportedAudioUseCase(projectRepository: projectRepository),
            audioPlaybackController: playbackController
        )

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.errorMessage != nil }

        XCTAssertEqual(
            viewModel.errorMessage,
            "This file's audio could no longer be located. Re-import it to restore waveform and playback access."
        )
        loadTask.cancel()
    }
}
