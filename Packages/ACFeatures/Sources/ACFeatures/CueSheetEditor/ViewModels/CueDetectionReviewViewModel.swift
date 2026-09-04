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
    public private(set) var displayData = WaveformDisplayData(buckets: [])
    public private(set) var fileDurationSeconds: Double = 0.001
    public var visibleRangeSeconds: ClosedRange<Double> = 0 ... 0.001
    /// Kept separate from `displayData` per SPEC.md §4.15 — updates
    /// continuously during playback while the waveform data is comparatively
    /// stable; bundling them would force needless recomputation on every
    /// playhead tick.
    public private(set) var playheadOffsetSeconds: Double?
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
            return WaveformMarker(id: index, offsetSeconds: start.offsetSeconds)
        }
    }

    private let observeProjectsUseCase: ObserveProjectsUseCase
    private let generateWaveformDetailUseCase: GenerateWaveformDetailUseCase
    private let updateCueUseCase: UpdateCueUseCase
    private let audioPlaybackController: AudioPlaybackController

    private var asset: AudioAsset?
    private var overviewPeaks: WaveformPeaks?
    private var hasLoadedInitialRange = false
    private var hasPreparedPlayback = false
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
        audioPlaybackController: AudioPlaybackController
    ) {
        self.projectID = projectID
        self.observeProjectsUseCase = observeProjectsUseCase
        self.generateWaveformDetailUseCase = generateWaveformDetailUseCase
        self.updateCueUseCase = updateCueUseCase
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

            if !hasLoadedInitialRange, let peaks = project.waveformPeaks, let asset = project.audioAsset {
                overviewPeaks = peaks
                fileDurationSeconds = max(asset.duration.seconds, 0.001)
                visibleRangeSeconds = 0 ... fileDurationSeconds
                displayData = Self.mapToDisplayData(peaks.buckets)
                hasLoadedInitialRange = true
            }
            await preparePlaybackIfNeeded()
        }
    }

    /// Begins observing `AudioPlaybackController.stateUpdates` for the
    /// playhead — a separate subscription from `load()`, since playback
    /// state has nothing to do with `Project` data.
    public func startObservingPlayback() {
        playbackObservationTask?.cancel()
        playbackObservationTask = Task { [weak self] in
            guard let self else { return }
            for await state in audioPlaybackController.stateUpdates {
                switch state {
                case let .playing(position), let .paused(position):
                    playheadOffsetSeconds = position
                case .stopped:
                    playheadOffsetSeconds = nil
                }
            }
        }
    }

    // MARK: - Zoom / pan

    /// Called whenever `WaveformView`'s zoom/pan gestures change
    /// `visibleRangeSeconds` — debounced/coalesced during a continuous
    /// gesture (SPEC.md §4.15), at a resolution driven by the view's actual
    /// pixel width, not a fixed constant.
    public func visibleRangeChanged(to newRange: ClosedRange<Double>, pixelWidth: Double) {
        visibleRangeSeconds = newRange
        self.pixelWidth = pixelWidth
        detailFetchTask?.cancel()
        detailFetchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.detailFetchDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.fetchDetailIfNeeded()
        }
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
        do {
            let buckets = try await generateWaveformDetailUseCase.generate(
                projectID: projectID,
                for: asset,
                startSeconds: visibleRangeSeconds.lowerBound,
                endSeconds: visibleRangeSeconds.upperBound,
                resolution: max(Int(pixelWidth), 1)
            )
            displayData = Self.mapToDisplayData(buckets)
        } catch {
            errorMessage = Self.reimportErrorMessage
        }
    }

    private func restoreOverviewIfNeeded() {
        guard let overviewPeaks, displayData.buckets.count != overviewPeaks.buckets.count else { return }
        displayData = Self.mapToDisplayData(overviewPeaks.buckets)
    }

    // MARK: - Reposition / split / merge

    public func boundaryDragged(markerID: Int, toSeconds seconds: Double) {
        guard cues.indices.contains(markerID), let oldStart = cues[markerID].startTimecode else { return }
        let oldEnd = oldStart.offsetSeconds + cues[markerID].duration.seconds
        let newDuration = MediaDuration(seconds: max(0, oldEnd - seconds))
        let cueID = cues[markerID].id
        Task { [weak self] in
            guard let self else { return }
            do {
                try await updateCueUseCase.edit(projectID: projectID, cueID: cueID) { existing in
                    Cue(
                        id: existing.id,
                        title: existing.title,
                        workNumber: existing.workNumber,
                        duration: newDuration,
                        rightHolders: existing.rightHolders,
                        isArrangementOfProtectedOriginal: existing.isArrangementOfProtectedOriginal,
                        source: existing.source,
                        startTimecode: Timecode(offsetSeconds: seconds),
                        notes: existing.notes
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

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
        Task { [weak self] in
            guard let self else { return }
            do {
                try await audioPlaybackController.play(from: start.offsetSeconds, until: end)
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

    private static func mapToDisplayData(_ buckets: [WaveformPeakBucket]) -> WaveformDisplayData {
        WaveformDisplayData(buckets: buckets.map { WaveformDisplayData.Bucket(min: $0.min, max: $0.max) })
    }
}
