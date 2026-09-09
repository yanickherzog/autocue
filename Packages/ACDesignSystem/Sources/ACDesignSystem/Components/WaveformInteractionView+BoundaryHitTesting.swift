import AppKit

/// Split into its own file purely to keep `WaveformInteractionNSView` under
/// this project's type-body-length lint limit — still the same type, just
/// via an extension, the same pattern `UpdateCueUseCase
/// +MoveBoundary.swift`/`CueDetectionReviewViewModel
/// +ClearImportedAudio.swift` already establish. Everything here is the
/// two-edges-per-cue hit-testing and contiguous-push-through live-preview
/// math (SPEC.md §4.19) — `WaveformInteractionNSView`'s primary file keeps
/// only the raw `NSEvent` handlers that call into it.
extension WaveformInteractionNSView {
    /// Mirrors `UpdateCueUseCase`'s own `contiguityEpsilonSeconds` (SPEC.md
    /// §4.19) — a plain number, not an import of `ACCore`, so this stays
    /// purely a live-preview heuristic; the real Use Case call is what
    /// actually enforces this value.
    static let contiguityEpsilonSeconds = 0.001

    /// Merge always targets "the preceding cue, the following cue" as a
    /// pair, regardless of which edge of the shared boundary was actually
    /// grabbed — dragging either the preceding cue's end marker or the
    /// following cue's start marker off the strip resolves to the same
    /// pair and the same merge call (SPEC.md §4.19).
    func followingCueIndex(for marker: WaveformBoundaryMarker) -> Int {
        switch marker {
        case let .start(cueIndex): cueIndex
        case let .end(cueIndex): cueIndex + 1
        }
    }

    func cueIndex(for marker: WaveformBoundaryMarker) -> Int {
        switch marker {
        case let .start(cueIndex): cueIndex
        case let .end(cueIndex): cueIndex
        }
    }

    /// Live-preview-only mirror of `UpdateCueUseCase.moveBoundary`'s full
    /// branch logic (SPEC.md §4.19) — computed fresh from the current
    /// `markers` on *every* drag frame, never from state captured once at
    /// drag start, so the preview can never drift from what the real commit
    /// will persist. Fires one `onBoundaryDragging` call for a single-cue
    /// move, two for an atomic contiguous push-through — mirroring
    /// `BoundaryMoveResult.updatedCues`'s own one-or-two shape exactly. The
    /// real commit (`onBoundaryDragged`, at release) still goes through the
    /// one real Use Case call, which re-derives everything from current
    /// repository state independently — this preview only needs to be
    /// *consistent* with it, computed via the identical clamp/push-through
    /// rules, not literally shared code.
    func previewDrag(of marker: WaveformBoundaryMarker, toSeconds seconds: Double) {
        switch marker {
        case let .end(cueIndex):
            for (previewMarker, previewSeconds) in Self.previewEndMove(
                markers: markers,
                cueIndex: cueIndex,
                requestedSeconds: seconds,
                fileDurationSeconds: fileDurationSeconds
            ) {
                onBoundaryDragging?(previewMarker, previewSeconds)
            }
        case let .start(cueIndex):
            for (previewMarker, previewSeconds) in Self.previewStartMove(
                markers: markers,
                cueIndex: cueIndex,
                requestedSeconds: seconds
            ) {
                onBoundaryDragging?(previewMarker, previewSeconds)
            }
        }
    }

    /// Pure preview computation for dragging `cueIndex`'s end marker —
    /// exactly mirrors `UpdateCueUseCase+MoveBoundary.swift`'s
    /// `planEndMove`: away/approaching a real gap (single-cue, clamped at
    /// the neighbor's *current* position, never crossing it), contiguous
    /// push-through (two-cue, clamped at the neighbor's own far/anchored
    /// end), and no-neighbor (bounded by this cue's own start and, if
    /// known, the file's own duration). No repository access — a pure
    /// function of already-available client-side state, so it can never
    /// disagree with what actually gets rendered from `markers` moments
    /// later, the bug this replaces (an earlier version of this file only
    /// clamped the *contiguous* branch, leaving a non-contiguous drag free
    /// to overshoot the neighbor with nothing to reconcile it back).
    static func previewEndMove(
        markers: [WaveformMarker],
        cueIndex: Int,
        requestedSeconds: Double,
        fileDurationSeconds: Double
    ) -> [(WaveformBoundaryMarker, Double)] {
        guard let cue = markers.first(where: { $0.id == cueIndex }) else { return [] }
        let ownStart = cue.offsetSeconds

        guard let successor = markers.first(where: { $0.id == cueIndex + 1 }) else {
            let newEnd = min(max(requestedSeconds, ownStart), fileDurationSeconds)
            return [(.end(cueIndex: cueIndex), newEnd)]
        }

        let successorStart = successor.offsetSeconds
        let gapBefore = successorStart - (ownStart + cue.durationSeconds)

        if requestedSeconds <= successorStart {
            let newEnd = max(requestedSeconds, ownStart)
            return [(.end(cueIndex: cueIndex), newEnd)]
        }
        if gapBefore <= contiguityEpsilonSeconds {
            let successorOwnEnd = successorStart + successor.durationSeconds
            let newEnd = min(requestedSeconds, successorOwnEnd)
            return [(.end(cueIndex: cueIndex), newEnd), (.start(cueIndex: cueIndex + 1), newEnd)]
        }
        // Non-contiguous, and the request tries to cross — clamp at the
        // neighbor's current position, never cross it.
        return [(.end(cueIndex: cueIndex), successorStart)]
    }

    /// The mirror image of `previewEndMove`, matching `planStartMove`.
    static func previewStartMove(
        markers: [WaveformMarker],
        cueIndex: Int,
        requestedSeconds: Double
    ) -> [(WaveformBoundaryMarker, Double)] {
        guard let cue = markers.first(where: { $0.id == cueIndex }) else { return [] }
        let ownEnd = cue.offsetSeconds + cue.durationSeconds

        guard let predecessor = markers.first(where: { $0.id == cueIndex - 1 }) else {
            let newStart = min(max(requestedSeconds, 0), ownEnd)
            return [(.start(cueIndex: cueIndex), newStart)]
        }

        let predecessorEnd = predecessor.offsetSeconds + predecessor.durationSeconds
        let gapBefore = cue.offsetSeconds - predecessorEnd

        if requestedSeconds >= predecessorEnd {
            let newStart = min(requestedSeconds, ownEnd)
            return [(.start(cueIndex: cueIndex), newStart)]
        }
        if gapBefore <= contiguityEpsilonSeconds {
            let newStart = max(requestedSeconds, predecessor.offsetSeconds)
            return [(.start(cueIndex: cueIndex), newStart), (.end(cueIndex: cueIndex - 1), newStart)]
        }
        // Non-contiguous, and the request tries to cross — clamp at the
        // neighbor's current position, never cross it.
        return [(.start(cueIndex: cueIndex), predecessorEnd)]
    }

    /// Every cue with a `startTimecode` contributes two independently
    /// hit-testable points — a start edge and an end edge (SPEC.md §4.19) —
    /// so both are checked, and the nearest (within `markerHitRadius`) wins.
    /// On a near-tie (a contiguous boundary, where a cue's end and its
    /// neighbor's start land on the same pixel), the following cue's start
    /// marker wins, an arbitrary but deterministic tie-break — it has no
    /// effect on which *behaviors* are reachable, only on which cue's
    /// fields visibly change first while dragging in the gap-opening
    /// direction.
    func hitTestMarker(at point: NSPoint) -> WaveformBoundaryMarker? {
        var candidates: [(marker: WaveformBoundaryMarker, distance: CGFloat)] = []
        for marker in markers {
            let startX = WaveformCoordinateMapper.pixelAtSeconds(
                marker.offsetSeconds,
                viewWidth: bounds.width,
                visibleRangeSeconds: visibleRangeSeconds
            )
            let startDistance = abs(startX - point.x)
            if startDistance <= markerHitRadius {
                candidates.append((.start(cueIndex: marker.id), startDistance))
            }
            let endX = WaveformCoordinateMapper.pixelAtSeconds(
                marker.offsetSeconds + marker.durationSeconds,
                viewWidth: bounds.width,
                visibleRangeSeconds: visibleRangeSeconds
            )
            let endDistance = abs(endX - point.x)
            if endDistance <= markerHitRadius {
                candidates.append((.end(cueIndex: marker.id), endDistance))
            }
        }
        guard let minDistance = candidates.map(\.distance).min() else { return nil }
        let ties = candidates.filter { abs($0.distance - minDistance) < 0.5 }
        if let start = ties.first(where: { candidate in
            if case .start = candidate.marker {
                return true
            }
            return false
        }) {
            return start.marker
        }
        return ties.first?.marker
    }
}
