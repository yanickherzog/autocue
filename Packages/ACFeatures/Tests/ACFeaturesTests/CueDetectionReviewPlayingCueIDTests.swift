import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `playingCueID`/`toggleRowPlayback` — `CueTableView`'s per-row play/stop
/// icon state (`CueDetectionReviewViewModel.swift`), split into its own file
/// for the same reason `CueDetectionPlaybackAndDisplayTests.swift` is
/// already separate from `CueDetectionReviewViewModelTests.swift`: this
/// project's type-body-length lint limit.
@MainActor
final class CueDetectionReviewPlayingCueIDTests: XCTestCase {
    func test_playMarkerSpan_setsPlayingCueID() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.playMarkerSpan(markerID: 0)

        XCTAssertEqual(viewModel.playingCueID, 0)
        loadTask.cancel()
    }

    func test_playFromPoint_clearsPlayingCueID() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.playMarkerSpan(markerID: 0)
        XCTAssertEqual(viewModel.playingCueID, 0)

        viewModel.playFromPoint(atSeconds: 5)

        XCTAssertNil(viewModel.playingCueID)
        loadTask.cancel()
    }

    func test_toggleRowPlayback_notCurrentlyPlayingThisRow_startsItsSpan() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let playbackController = env.playbackController
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.toggleRowPlayback(markerID: 0)

        try await waitUntilCueDetectionReviewConditionMet { await !(playbackController.playCalls.isEmpty) }
        let calls = await playbackController.playCalls
        XCTAssertEqual(calls.first?.from, 10)
        XCTAssertEqual(calls.first?.until, 40)
        XCTAssertEqual(viewModel.playingCueID, 0)
        loadTask.cancel()
    }

    func test_toggleRowPlayback_alreadyPlayingThisRow_stopsPlayback() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let playbackController = env.playbackController
        let loadTask = Task { await viewModel.load() }
        // playingCueID is only cleared once .stopped comes back through
        // stateUpdates, so this test — unlike the others above — needs the
        // stream actually observed (`CueDetectionPlaybackAndDisplayTests`'s
        // pattern).
        let observeTask = Task { viewModel.startObservingPlayback() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.toggleRowPlayback(markerID: 0)
        try await waitUntilCueDetectionReviewConditionMet { viewModel.playingCueID == 0 }

        viewModel.toggleRowPlayback(markerID: 0)

        try await waitUntilCueDetectionReviewConditionMet { await playbackController.stopCallCount == 1 }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.playingCueID == nil }
        loadTask.cancel()
        observeTask.cancel()
    }

    func test_togglePlayback_start_clearsPlayingCueID() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.playMarkerSpan(markerID: 0)
        XCTAssertEqual(viewModel.playingCueID, 0)

        // isPlaying is still false here, guaranteed: playMarkerSpan only
        // schedules a Task and returns synchronously, and nothing has
        // suspended yet to let it (or startObservingPlayback's stream
        // consumer) actually run — so this deterministically exercises
        // togglePlayback's "start," not "stop," branch.
        viewModel.togglePlayback()

        XCTAssertNil(viewModel.playingCueID)
        loadTask.cancel()
    }
}
