import ACCore
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
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
