import ACCore
import ACDesignSystem
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// Split from `CueDetectionReviewViewModelTests` purely to stay under this
/// project's type-body-length lint limit — same shared fixtures
/// (`CueDetectionReviewTestEnvironment.swift`), same ViewModel under test.
@MainActor
final class CueDetectionPlaybackAndDisplayTests: XCTestCase {
    // MARK: - Explicit play/stop toggle (button + spacebar)

    func test_togglePlayback_whenNotPlaying_playsFromZero_whenNothingHasPlayedYet() async throws {
        let env = makeCueDetectionReviewEnvironment(cues: [])
        let viewModel = env.viewModel
        let playbackController = env.playbackController
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { await playbackController.prepareCallCount == 1 }

        viewModel.togglePlayback()

        try await waitUntilCueDetectionReviewConditionMet { await !(playbackController.playCalls.isEmpty) }
        let calls = await playbackController.playCalls
        XCTAssertEqual(calls.first?.from, 0)
        XCTAssertNil(calls.first?.until, "a manual toggle is never bounded to one cue's span")
        loadTask.cancel()
    }

    func test_togglePlayback_afterASeek_resumesFromThatPosition_notZero() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let playbackController = env.playbackController
        let loadTask = Task { await viewModel.load() }
        let observeTask = Task { viewModel.startObservingPlayback() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.playMarkerSpan(markerID: 0) // seeks to 10, bounded until 40
        try await waitUntilCueDetectionReviewConditionMet { viewModel.isPlaying }

        viewModel.togglePlayback() // stop
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.isPlaying }

        viewModel.togglePlayback() // resume — should be from 10, not 0
        try await waitUntilCueDetectionReviewConditionMet { await playbackController.playCalls.count == 2 }
        let calls = await playbackController.playCalls
        XCTAssertEqual(calls.last?.from, 10)
        XCTAssertNil(calls.last?.until)
        loadTask.cancel()
        observeTask.cancel()
    }

    func test_togglePlayback_whilePlaying_stops() async throws {
        let env = makeCueDetectionReviewEnvironment(cues: [])
        let viewModel = env.viewModel
        let playbackController = env.playbackController
        let loadTask = Task { await viewModel.load() }
        let observeTask = Task { viewModel.startObservingPlayback() }
        try await waitUntilCueDetectionReviewConditionMet { await playbackController.prepareCallCount == 1 }

        viewModel.togglePlayback() // start
        try await waitUntilCueDetectionReviewConditionMet { viewModel.isPlaying }

        viewModel.togglePlayback() // stop
        try await waitUntilCueDetectionReviewConditionMet { await playbackController.stopCallCount == 1 }
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.isPlaying }
        loadTask.cancel()
        observeTask.cancel()
    }

    func test_isPlaying_tracksStateUpdates_pausedIsNotPlaying() async throws {
        let env = makeCueDetectionReviewEnvironment(cues: [])
        let viewModel = env.viewModel
        let playbackController = env.playbackController
        let loadTask = Task { await viewModel.load() }
        let observeTask = Task { viewModel.startObservingPlayback() }
        try await waitUntilCueDetectionReviewConditionMet { await playbackController.prepareCallCount == 1 }

        await playbackController.emit(.playing(positionSeconds: 5))
        try await waitUntilCueDetectionReviewConditionMet { viewModel.isPlaying }

        await playbackController.emit(.paused(positionSeconds: 5))
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.isPlaying }
        XCTAssertEqual(viewModel.playheadOffsetSeconds, 5, "paused still reports a playhead position")
        loadTask.cancel()
        observeTask.cancel()
    }

    // MARK: - `displayData.representedRangeSeconds` (waveform-lag fix)

    func test_initialLoad_displayDataRepresentsTheWholeFile() async throws {
        let env = makeCueDetectionReviewEnvironment(cues: [])
        let viewModel = env.viewModel
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.displayData.buckets.isEmpty }

        XCTAssertEqual(viewModel.displayData.representedRangeSeconds, 0 ... viewModel.fileDurationSeconds)
        loadTask.cancel()
    }

    func test_afterOnDemandDetailFetch_displayDataRepresentsExactlyTheFetchedRange() async throws {
        let env = makeCueDetectionReviewEnvironment(cues: [])
        let viewModel = env.viewModel
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.displayData.buckets.isEmpty }
        let overviewRange = viewModel.displayData.representedRangeSeconds

        // Zoom in tight enough to cross the on-demand-detail threshold.
        let narrowRange = 0.0 ... (viewModel.fileDurationSeconds / 100)
        viewModel.visibleRangeChanged(to: narrowRange, pixelWidth: 2000)

        try await waitUntilCueDetectionReviewConditionMet(timeout: 3) {
            viewModel.displayData.representedRangeSeconds != overviewRange
        }
        XCTAssertEqual(viewModel.displayData.representedRangeSeconds, narrowRange)
        loadTask.cancel()
    }
}
