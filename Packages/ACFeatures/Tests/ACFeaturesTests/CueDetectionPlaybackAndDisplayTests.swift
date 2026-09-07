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

    /// Regression test for the pan/zoom-out lag: panning or zooming out
    /// past what the currently-held (narrow, on-demand-detail) data covers
    /// used to leave `displayData` positioned correctly but simply not
    /// covering the newly-visible area at all, until the debounced fetch
    /// resolved — a real, visible lag distinct from (and not fixed by) the
    /// zoom-in fix from the previous round. `visibleRangeChanged` must now
    /// fall back to the whole-file overview *immediately*, synchronously,
    /// the moment the new range escapes the currently-held one — not wait
    /// for any debounce.
    func test_visibleRangeChangedToRangeOutsideCurrentData_immediatelyFallsBackToOverview() async throws {
        let env = makeCueDetectionReviewEnvironment(cues: [])
        let viewModel = env.viewModel
        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.displayData.buckets.isEmpty }
        let overviewRange = viewModel.displayData.representedRangeSeconds

        // Zoom in and let the on-demand detail fetch resolve first, so
        // displayData now represents only a narrow sub-range.
        let narrowRange = 0.0 ... (viewModel.fileDurationSeconds / 100)
        viewModel.visibleRangeChanged(to: narrowRange, pixelWidth: 2000)
        try await waitUntilCueDetectionReviewConditionMet(timeout: 3) {
            viewModel.displayData.representedRangeSeconds == narrowRange
        }

        // Pan/zoom-out to a range the held narrow data doesn't cover at
        // all — this must fall back to overview synchronously, before the
        // new debounced fetch has any chance to resolve.
        let farRange = (viewModel.fileDurationSeconds / 2) ... viewModel.fileDurationSeconds
        viewModel.visibleRangeChanged(to: farRange, pixelWidth: 2000)

        XCTAssertEqual(viewModel.displayData.representedRangeSeconds, overviewRange)
        loadTask.cancel()
    }

    // MARK: - Cross-cycle latch resets (found by deliberate sweep)

    /// Found by live reproduction, not inference: `AudioPlaybackController
    /// .stateUpdates` is one `AsyncStream` for this window's entire
    /// lifetime. `startObservingPlayback()` used to cancel-and-restart its
    /// `for await` loop every time `CueDetectionReviewView` re-appeared
    /// (once per import/clear cycle) — but cancelling the `Task` consuming
    /// an `AsyncStream` terminates the *stream*, not just that one
    /// consumer, so every call after the first left the subscription
    /// permanently dead: the playhead never updated again, and `isPlaying`
    /// stuck at whatever it was, so `togglePlayback()` always took the
    /// "start" branch instead of ever toggling to "stop." This simulates a
    /// second cycle's re-appearance calling `startObservingPlayback()`
    /// again on the same long-lived ViewModel and proves the subscription
    /// set up by the *first* call is still the one delivering events.
    func test_startObservingPlayback_calledAgainOnLaterCycle_doesNotKillTheExistingSubscription() async throws {
        let env = makeCueDetectionReviewEnvironment(cues: [])
        let viewModel = env.viewModel
        let playbackController = env.playbackController

        viewModel.startObservingPlayback()
        // The real trigger: CueDetectionReviewView's `.task` calling this
        // again when the review screen re-appears after a clear/re-import
        // cycle, on the same `audioPlaybackController` instance (it's
        // constructed once per window, never per cycle).
        viewModel.startObservingPlayback()

        await playbackController.emit(.playing(positionSeconds: 5))
        try await waitUntilCueDetectionReviewConditionMet { viewModel.isPlaying }
        XCTAssertEqual(viewModel.playheadOffsetSeconds, 5)

        await playbackController.emit(.stopped)
        try await waitUntilCueDetectionReviewConditionMet { !viewModel.isPlaying }
        XCTAssertNil(viewModel.playheadOffsetSeconds)
    }

    /// Found by a deliberate sweep for the same bug class already fixed
    /// twice this session (`AudioImportViewModel`/`CueDetectionViewModel`'s
    /// never-reset "has this already happened" latches) — not by a reported
    /// symptom. `hasLoadedInitialRange`/`hasPreparedPlayback` never resetting
    /// meant a second import cycle's waveform/playback would silently keep
    /// pointing at the *first* cycle's file. See `resetForNewImportCycle()`'s
    /// doc comment.
    func test_clearThenNewImport_reloadsWaveformAndPreparesPlaybackForTheNewFile() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let playbackController = env.playbackController
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }
        try await waitUntilCueDetectionReviewConditionMet { await playbackController.prepareCallCount == 1 }
        let firstFileDuration = viewModel.fileDurationSeconds

        viewModel.clearImportedAudio()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.audioAsset == nil
        }

        try await assertReimportReloadsWaveformAndPlayback(
            viewModel: viewModel,
            projectRepository: projectRepository,
            playbackController: playbackController,
            project: project,
            firstFileDuration: firstFileDuration
        )
        loadTask.cancel()
    }

    /// Split out of the test body above purely to keep it under this
    /// project's function-body-length lint limit — still exercises the
    /// exact same assertions, just as a shared helper.
    private func assertReimportReloadsWaveformAndPlayback(
        viewModel: CueDetectionReviewViewModel,
        projectRepository: InMemoryProjectRepository,
        playbackController: InMemoryAudioPlaybackController,
        project: Project,
        firstFileDuration: Double
    ) async throws {
        // A genuinely different second file: different bookmark, different
        // duration, different waveform peaks — simulating the real
        // import/waveform-generation/detection path's end result, the same
        // way `ClearImportedAudioUseCase`'s own doc comment reasons about
        // "this specific audio."
        let secondAsset = AudioAsset(
            originalFileName: "second-file.wav",
            securityScopedBookmark: Data([0x02]),
            duration: MediaDuration(seconds: 999),
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            importedAt: Date(timeIntervalSince1970: 0)
        )
        let secondPeaks = WaveformPeaks(
            audioAssetID: secondAsset.id,
            resolution: 8,
            buckets: (0 ..< 8).map { _ in WaveformPeakBucket(min: -0.9, max: 0.9) }
        )
        let secondCue = makeCueDetectionReviewCue(startSeconds: 5, duration: 20)
        try await projectRepository.update(id: project.id) { current in
            Project(
                id: current.id,
                name: current.name,
                createdAt: current.createdAt,
                updatedAt: Date(),
                audioAsset: secondAsset,
                waveformPeaks: secondPeaks,
                setup: current.setup,
                cues: [secondCue],
                people: current.people,
                labels: current.labels
            )
        }

        try await waitUntilCueDetectionReviewConditionMet { viewModel.fileDurationSeconds != firstFileDuration }
        XCTAssertEqual(viewModel.fileDurationSeconds, 999, accuracy: 0.001)
        XCTAssertEqual(
            viewModel.displayData.buckets.count, 8,
            "must reload the *new* file's waveform, not keep the first cycle's"
        )

        try await waitUntilCueDetectionReviewConditionMet { await playbackController.prepareCallCount == 2 }
        let lastBookmark = await playbackController.lastPreparedBookmark
        XCTAssertEqual(
            lastBookmark, secondAsset.securityScopedBookmark,
            "must prepare playback with the *new* file's bookmark, not keep pointing at the first cycle's"
        )
    }
}
