import ACCore
import ACDesignSystem
import Foundation

/// Split into its own file purely to keep `CueDetectionReviewViewModel`
/// under this project's type-body-length lint limit — still the same type,
/// just via an extension, the same pattern `+ClearImportedAudio.swift`
/// already establishes. See `updateCueUseCase`'s doc comment in the primary
/// declaration for why it isn't `private`.
public extension CueDetectionReviewViewModel {
    /// The waveform's drag-to-reposition gesture now targets either edge of
    /// a cue (SPEC.md §4.19, "Boundary markers: contiguous vs.
    /// non-contiguous") — `WaveformBoundaryMarker`'s plain cue-index is
    /// translated to a real `Cue.ID` here, at the point it crosses back into
    /// `ACCore`, the same adapter-at-the-edge translation `mergeRequested`
    /// already performs for its own marker index. Whether this ends up
    /// writing one cue or two (an atomic contiguous push-through) is
    /// entirely `UpdateCueUseCase.moveBoundary`'s decision, not this
    /// ViewModel's — it just forwards the request.
    func boundaryDragged(marker: WaveformBoundaryMarker, toSeconds seconds: Double) {
        let index = Self.cueIndex(for: marker)
        guard cues.indices.contains(index) else { return }
        let cueID = cues[index].id
        let boundaryMarkerKind: BoundaryMarkerKind = switch marker {
        case .start: .start(cueID)
        case .end: .end(cueID)
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await updateCueUseCase.moveBoundary(
                    projectID: projectID,
                    marker: boundaryMarkerKind,
                    toOffsetSeconds: seconds
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private extension CueDetectionReviewViewModel {
    static func cueIndex(for marker: WaveformBoundaryMarker) -> Int {
        switch marker {
        case let .start(cueIndex): cueIndex
        case let .end(cueIndex): cueIndex
        }
    }
}
