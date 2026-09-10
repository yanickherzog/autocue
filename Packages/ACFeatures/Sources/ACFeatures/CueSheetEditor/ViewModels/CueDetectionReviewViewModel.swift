import ACCore
import ACDesignSystem
import Foundation

/// Backs `CueDetectionReviewView` (`ROADMAP.md` D9/T9.3) — the waveform
/// review/correction surface: zoom, pan, drag-to-reposition, split, merge,
/// and playback. Owns `visibleRangeSeconds` (SPEC.md §4.15) and maps
/// `ACCore` types to `ACDesignSystem`'s domain-free `WaveformDisplayData`/
/// `WaveformMarker` at the point this screen renders them.
///
/// **One live subscription is the single source of truth for `cues` and the
/// waveform overview** — never a separately-mutated cache. A boundary
/// drag/split/merge writes through `UpdateCueUseCase`, and the resulting
/// live-stream re-emission is what updates `cues` here, not a locally
/// applied optimistic mutation. `visibleRangeSeconds` is separate,
/// ViewModel-owned UI state, untouched by that re-emission, so a structural
/// edit never resets the user's current zoom/pan position.
@Observable
@MainActor
public final class CueDetectionReviewViewModel {
    public let projectID: Project.ID
    public private(set) var cues: [Cue] = []
    /// Kept in step with the live subscription below, for `+TableRows.swift`'s
    /// TC In/TC Out (SPEC.md §4.3/§4.9). Not `private`: needed there too.
    var timecodeFrameRate: TimecodeFrameRate = .fps25
    var timecodeStart: Timecode?
    /// `internal(set)`: reset from `+ClearImportedAudio.swift`'s `resetForNewImportCycle()`.
    public internal(set) var displayData = WaveformDisplayData(buckets: [])
    public internal(set) var fileDurationSeconds: Double = 0.001
    public var visibleRangeSeconds: ClosedRange<Double> = 0 ... 0.001
    /// Kept separate from `displayData` per SPEC.md §4.15 — updates
    /// continuously during playback while the waveform data is comparatively
    /// stable; bundling them would force needless recomputation on every
    /// playhead tick.
    public private(set) var playheadOffsetSeconds: Double?
    /// Drives the play/stop button's icon and spacebar's toggle direction —
    /// `true` only while `AudioPlaybackController.stateUpdates` reports
    /// `.playing`, `false` for both `.paused` and `.stopped` (this screen
    /// never pauses, only stops, per SPEC.md §4.20's play-or-stop model).
    public private(set) var isPlaying = false
    /// Wherever playback last was — updated on every seek (click-to-play,
    /// play-marker-span) and by the live `stateUpdates` subscription while
    /// playing/paused. Read by `togglePlayback()` so pressing spacebar after
    /// a stop resumes from "current position" rather than always restarting
    /// at the file's beginning — `0` if nothing has played yet this session.
    /// Not `private` — reset from `+ClearImportedAudio.swift`, same reason as `overviewPeaks` et al. below.
    var lastKnownPlaybackPositionSeconds: Double = 0
    /// Set on a thrown `GenerateWaveformDetailUseCase`/
    /// `AudioPlaybackController` error — e.g. a `.plainFallback` bookmark
    /// that no longer resolves on a reopened project (SPEC.md §4.10, §4.21).
    /// `CueDetectionReviewView` binds `.errorAlert(message:)` to this.
    public var errorMessage: String?

    /// `WaveformView`'s domain-free marker adapters — `id` is the marker's
    /// index in `cues`, threaded back through every gesture closure so
    /// handlers here know exactly which `Cue` moved. Cues with no
    /// `startTimecode` have no waveform position to click on and are
    /// correctly excluded (SPEC.md §4.15).
    public var markers: [WaveformMarker] {
        cues.enumerated().compactMap { index, cue in
            guard let start = cue.startTimecode else { return nil }
            return WaveformMarker(id: index, offsetSeconds: start.offsetSeconds, durationSeconds: cue.duration.seconds)
        }
    }

    private let observeProjectsUseCase: ObserveProjectsUseCase
    private let generateWaveformDetailUseCase: GenerateWaveformDetailUseCase
    /// Not `private`: read from this type's `+BoundaryDragging.swift`/
    /// `+ClearImportedAudio.swift` extensions (each split into its own file
    /// purely to stay under this project's type-body-length lint limit) —
    /// still `internal`, never exposed as public API.
    let updateCueUseCase: UpdateCueUseCase
    let clearImportedAudioUseCase: ClearImportedAudioUseCase
    let audioPlaybackController: AudioPlaybackController

    private var asset: AudioAsset?
    /// These three, plus `lastKnownPlaybackPositionSeconds` above, aren't
    /// `private` — reset from `+ClearImportedAudio.swift`'s
    /// `resetForNewImportCycle()`, same cross-file-extension reason
    /// `clearImportedAudioUseCase` above isn't `private` either.
    var overviewPeaks: WaveformPeaks?
    var hasLoadedInitialRange = false
    var hasPreparedPlayback = false
    /// Unlike the latches above, never reset across cycles — see `startObservingPlayback()`.
    private var hasStartedObservingPlayback = false
    private var pixelWidth: Double = 800
    /// `@ObservationIgnored` + `nonisolated(unsafe)`: `deinit` is never
    /// actor-isolated, even on a `@MainActor` class — same pattern
    /// `SetupViewModel.saveTask`/`ProjectLibraryViewModel` already establish.
    @ObservationIgnored
    private nonisolated(unsafe) var detailFetchTask: Task<Void, Never>?
    @ObservationIgnored
    private nonisolated(unsafe) var playbackObservationTask: Task<Void, Never>?

    private static let reimportErrorMessage =
        "This file's audio could no longer be located. Re-import it to restore waveform and playback access."
    private static let detailFetchDebounceNanoseconds: UInt64 = 150_000_000

    public init(
        projectID: Project.ID,
        observeProjectsUseCase: ObserveProjectsUseCase,
        generateWaveformDetailUseCase: GenerateWaveformDetailUseCase,
        updateCueUseCase: UpdateCueUseCase,
        clearImportedAudioUseCase: ClearImportedAudioUseCase,
        audioPlaybackController: AudioPlaybackController
    ) {
        self.projectID = projectID
        self.observeProjectsUseCase = observeProjectsUseCase
        self.generateWaveformDetailUseCase = generateWaveformDetailUseCase
        self.updateCueUseCase = updateCueUseCase
        self.clearImportedAudioUseCase = clearImportedAudioUseCase
        self.audioPlaybackController = audioPlaybackController
    }

    deinit {
        detailFetchTask?.cancel()
        playbackObservationTask?.cancel()
    }

    /// Runs for the whole screen's lifetime (called once from the hosting
    /// View's `.task`) — every subsequent mutation (split/merge/reposition,
    /// or a fresh detection run) republishes here live.
    public func load() async {
        for await projects in observeProjectsUseCase.observeAll() {
            guard let project = projects.first(where: { $0.id == projectID }) else { continue }
            cues = project.cues
            asset = project.audioAsset
            timecodeFrameRate = project.setup.timecodeFrameRate
            timecodeStart = project.setup.timecodeStart

            if !hasLoadedInitialRange, let peaks = project.waveformPeaks, let asset = project.audioAsset {
                overviewPeaks = peaks
                fileDurationSeconds = max(asset.duration.seconds, 0.001)
                visibleRangeSeconds = 0 ... fileDurationSeconds
                displayData = Self.mapToDisplayData(peaks.buckets, representedRangeSeconds: visibleRangeSeconds)
                hasLoadedInitialRange = true
            }
            await preparePlaybackIfNeeded()
        }
    }

    /// Begins observing `AudioPlaybackController.stateUpdates` for the
    /// playhead — a separate subscription from `load()`, since playback
    /// state has nothing to do with `Project` data.
    ///
    /// **Idempotent — runs at most once per instance, ever.**
    /// `CueDetectionReviewView`'s hosting `.task` calls this every time the
    /// review screen re-appears (once per import/clear cycle). This used to
    /// cancel-and-restart its `for await` loop on every call, but
    /// `stateUpdates` is one `AsyncStream` for this window's whole
    /// lifetime, and cancelling the `Task` consuming an `AsyncStream`
    /// terminates the *stream*, not just that consumer — so every call
    /// after the first left the subscription permanently dead (confirmed
    /// live: the playhead stopped updating and `isPlaying` froze, so
    /// `togglePlayback()` always took the "start" branch). Fix: subscribe
    /// exactly once; `audioPlaybackController` never changes, so there's
    /// nothing later cycles need to re-subscribe to. See
    /// `CueDetectionPlaybackAndDisplayTests`'s regression test for the
    /// full account.
    public func startObservingPlayback() {
        guard !hasStartedObservingPlayback else { return }
        hasStartedObservingPlayback = true
        playbackObservationTask = Task { [weak self] in
            guard let self else { return }
            for await state in audioPlaybackController.stateUpdates {
                switch state {
                case let .playing(position):
                    playheadOffsetSeconds = position
                    lastKnownPlaybackPositionSeconds = position
                    isPlaying = true
                case let .paused(position):
                    playheadOffsetSeconds = position
                    lastKnownPlaybackPositionSeconds = position
                    isPlaying = false
                case .stopped:
                    playheadOffsetSeconds = nil
                    isPlaying = false
                }
            }
        }
    }

    // MARK: - Zoom / pan

    /// Backs the header row's +/- zoom buttons (`CueDetectionReviewView`) —
    /// the button-triggered equivalent of `WaveformView`'s pinch/scroll zoom
    /// gestures, which call `visibleRangeChanged` directly from inside that
    /// view. Buttons live outside `WaveformView` (moved to the header, next
    /// to the playback/clear-audio controls), so zooming from a button goes
    /// through this method instead, reusing the same `WaveformCoordinateMapper`
    /// math and funneling into the same `visibleRangeChanged` path so
    /// on-demand detail refetch stays a single code path regardless of
    /// which input triggered the zoom.
    public func zoom(by factor: Double) {
        let center = (visibleRangeSeconds.lowerBound + visibleRangeSeconds.upperBound) / 2
        let newRange = WaveformCoordinateMapper.zooming(
            visibleRangeSeconds,
            by: factor,
            aroundSeconds: center,
            fileDurationSeconds: fileDurationSeconds
        )
        visibleRangeChanged(to: newRange, pixelWidth: pixelWidth)
    }

    /// Called whenever `WaveformView`'s zoom/pan gestures change
    /// `visibleRangeSeconds` — debounced/coalesced during a continuous
    /// gesture (SPEC.md §4.15), at a resolution driven by the view's actual
    /// pixel width, not a fixed constant.
    public func visibleRangeChanged(to newRange: ClosedRange<Double>, pixelWidth: Double) {
        visibleRangeSeconds = newRange
        self.pixelWidth = pixelWidth
        // Zooming *in* always still has overlapping data to reposition
        // correctly (the existing displayData's represented range fully
        // contains the new, narrower one) — no need to touch displayData
        // here at all. Zooming *out* or panning past what's currently held
        // reveals area that data simply doesn't cover, so repositioning it
        // alone would draw a correctly-placed but incomplete/wrong picture
        // for the newly-revealed area. Falling back immediately to the
        // always-available, whole-file overview — which by definition
        // covers *any* range — guarantees something geometrically correct
        // is visible right away in that case, without the flash back to
        // coarse that would happen if this ran unconditionally on every
        // pan/zoom, however small.
        if !Self.range(newRange, isFullyContainedIn: displayData.representedRangeSeconds), let overviewPeaks {
            displayData = Self.mapToDisplayData(
                overviewPeaks.buckets,
                representedRangeSeconds: 0 ... fileDurationSeconds
            )
        }
        detailFetchTask?.cancel()
        detailFetchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.detailFetchDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.fetchDetailIfNeeded()
        }
    }

    private static func range(_ inner: ClosedRange<Double>, isFullyContainedIn outer: ClosedRange<Double>) -> Bool {
        inner.lowerBound >= outer.lowerBound && inner.upperBound <= outer.upperBound
    }

    private func fetchDetailIfNeeded() async {
        guard let asset, fileDurationSeconds > 0 else { return }
        let visibleWidth = visibleRangeSeconds.upperBound - visibleRangeSeconds.lowerBound
        let overviewSecondsPerBucket = fileDurationSeconds / Double(overviewPeaks?.resolution ?? 4096)
        let overviewBucketsInRange = overviewSecondsPerBucket > 0 ? visibleWidth / overviewSecondsPerBucket : .infinity

        guard overviewBucketsInRange < pixelWidth else {
            restoreOverviewIfNeeded()
            return
        }
        let requestedRange = visibleRangeSeconds
        do {
            let buckets = try await generateWaveformDetailUseCase.generate(
                projectID: projectID,
                for: asset,
                startSeconds: requestedRange.lowerBound,
                endSeconds: requestedRange.upperBound,
                resolution: max(Int(pixelWidth), 1)
            )
            displayData = Self.mapToDisplayData(buckets, representedRangeSeconds: requestedRange)
        } catch {
            errorMessage = Self.reimportErrorMessage
        }
    }

    private func restoreOverviewIfNeeded() {
        guard let overviewPeaks, displayData.buckets.count != overviewPeaks.buckets.count else { return }
        displayData = Self.mapToDisplayData(overviewPeaks.buckets, representedRangeSeconds: 0 ... fileDurationSeconds)
    }

    // MARK: - Split / merge

    /// An ⌥-click within a cue's plotted region — SPEC.md §4.15. Clicks
    /// outside any cue's region (silence/gap space) find no containing cue
    /// and are correctly a no-op.
    public func splitRequested(atSeconds seconds: Double) {
        guard let cueID = cues.first(where: { cue in
            guard let start = cue.startTimecode else { return false }
            let end = start.offsetSeconds + cue.duration.seconds
            return seconds > start.offsetSeconds && seconds < end
        })?.id else { return }

        Task { [weak self] in
            guard let self else { return }
            // A too-close-to-endpoint rejection (`splitOffsetTooCloseToEndpoint`)
            // is an expected, silent no-op per SPEC.md §4.15 — not a real error.
            _ = try? await updateCueUseCase.split(projectID: projectID, cueID: cueID, atOffsetSeconds: seconds)
        }
    }

    /// Dragging a marker off the waveform strip — eligibility (genuine
    /// contiguity with the preceding cue) is `UpdateCueUseCase.merge`'s own
    /// job; an ineligible attempt throws `mergeNotContiguous`, silently
    /// absorbed here as the no-op SPEC.md §4.15 specifies ("no merge
    /// affordance appears, the drag cancels on release").
    public func mergeRequested(markerID: Int) {
        guard cues.indices.contains(markerID), markerID > 0 else { return }
        let precedingCueID = cues[markerID - 1].id
        let followingCueID = cues[markerID].id
        Task { [weak self] in
            guard let self else { return }
            _ = try? await updateCueUseCase.merge(
                projectID: projectID,
                precedingCueID: precedingCueID,
                cueID: followingCueID
            )
        }
    }

    // MARK: - Playback

    public func playFromPoint(atSeconds seconds: Double) {
        lastKnownPlaybackPositionSeconds = seconds
        Task { [weak self] in
            guard let self else { return }
            do {
                try await audioPlaybackController.play(from: seconds, until: nil)
            } catch {
                errorMessage = Self.reimportErrorMessage
            }
        }
    }

    public func playMarkerSpan(markerID: Int) {
        guard cues.indices.contains(markerID), let start = cues[markerID].startTimecode else { return }
        let end = start.offsetSeconds + cues[markerID].duration.seconds
        lastKnownPlaybackPositionSeconds = start.offsetSeconds
        Task { [weak self] in
            guard let self else { return }
            do {
                try await audioPlaybackController.play(from: start.offsetSeconds, until: end)
            } catch {
                errorMessage = Self.reimportErrorMessage
            }
        }
    }

    /// Stops any in-flight playback this screen started — called explicitly
    /// when this window is about to close (`AutoCue/ProjectWindowPlaybackStopper.swift`),
    /// the same `NSWindow.willCloseNotification` pattern already established
    /// for a pending debounced Setup save (`ProjectWindowSaveFlusher`) and
    /// window-frame persistence (`ProjectWindowFrameSaver`). Without an
    /// explicit hook here, closing this window while audio is playing left
    /// it running and audible with no way to stop it — the play/stop button
    /// and spacebar handler live in this now-closed window, and neither this
    /// type's own `deinit` nor `AudioPlaybackControllerImpl`'s can reach
    /// `stop()`: it's `async` on an actor, and `deinit` is synchronous.
    /// Safe to call even if nothing is currently playing (`stop()` is a
    /// no-op in that case).
    public func stopPlaybackForWindowClose() async {
        await audioPlaybackController.stop()
    }

    /// The explicit play/stop control (button + spacebar) — standard DAW
    /// toggle semantics: playing stops it, anything else starts it from
    /// wherever playback last was (`lastKnownPlaybackPositionSeconds`,
    /// `0` if nothing has played yet this session). Never bounded (`until:
    /// nil`) — a manual toggle is a free transport action, not tied to any
    /// one cue's span.
    public func togglePlayback() {
        if isPlaying {
            Task { [weak self] in await self?.audioPlaybackController.stop() }
            return
        }
        let startSeconds = lastKnownPlaybackPositionSeconds
        Task { [weak self] in
            guard let self else { return }
            do {
                try await audioPlaybackController.play(from: startSeconds, until: nil)
            } catch {
                errorMessage = Self.reimportErrorMessage
            }
        }
    }

    private func preparePlaybackIfNeeded() async {
        guard !hasPreparedPlayback, let asset else { return }
        hasPreparedPlayback = true
        do {
            try await audioPlaybackController.prepare(
                securityScopedBookmark: asset.securityScopedBookmark,
                mode: asset.bookmarkAccessMode
            )
        } catch {
            errorMessage = Self.reimportErrorMessage
        }
    }

    private static func mapToDisplayData(
        _ buckets: [WaveformPeakBucket],
        representedRangeSeconds: ClosedRange<Double>
    ) -> WaveformDisplayData {
        WaveformDisplayData(
            buckets: buckets.map { WaveformDisplayData.Bucket(min: $0.min, max: $0.max) },
            representedRangeSeconds: representedRangeSeconds
        )
    }
}
