import ACCore
import ACDesignSystem
import Foundation

/// Split into its own file purely to keep `CueDetectionReviewViewModel`
/// under this project's type-body-length lint limit — still the same type,
/// just via an extension. See `clearImportedAudioUseCase`'s doc comment in
/// the primary declaration for why it (and `audioPlaybackController`)
/// aren't `private`.
public extension CueDetectionReviewViewModel {
    /// The "wrong file, start over" affordance — clears `audioAsset`
    /// (cascading to `waveformPeaks`/`cues`, `ClearImportedAudioUseCase`'s
    /// own doc comment has the full reasoning) and stops any playback in
    /// progress first, since its `AudioAsset`/security-scoped bookmark are
    /// about to become invalid. `CueSheetSectionViewModel`'s resume-state
    /// routing reacts to the resulting live snapshot on its own — this
    /// method never navigates directly.
    func clearImportedAudio() {
        Task { [weak self] in
            guard let self else { return }
            await audioPlaybackController.stop()
            do {
                try await clearImportedAudioUseCase.clear(projectID: projectID)
                resetForNewImportCycle()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private extension CueDetectionReviewViewModel {
    /// Resets every piece of state that was gated behind a one-time "has
    /// this already happened" latch, so a *new* import cycle's
    /// waveform/playback actually loads instead of silently keeping the
    /// *previous* cycle's data. Found by a deliberate sweep for the same
    /// "long-lived per-window ViewModel latch that never resets across
    /// clear/re-import cycles" shape already fixed twice elsewhere this
    /// session (`AudioImportViewModel`/`CueDetectionViewModel`'s
    /// `resetIfNeeded()`): `hasLoadedInitialRange` never resetting meant a
    /// second cycle's `load()` would never re-populate the waveform from
    /// the *new* file; `hasPreparedPlayback` never resetting meant playback
    /// would keep pointing at the *first* cycle's file — not a hang, a
    /// silent wrong-audio bug. `cues`/`asset` don't need resetting —
    /// `load()` reassigns both unconditionally on every emission regardless.
    func resetForNewImportCycle() {
        hasLoadedInitialRange = false
        hasPreparedPlayback = false
        overviewPeaks = nil
        displayData = WaveformDisplayData(buckets: [])
        fileDurationSeconds = 0.001
        visibleRangeSeconds = 0 ... 0.001
        lastKnownPlaybackPositionSeconds = 0
    }
}
