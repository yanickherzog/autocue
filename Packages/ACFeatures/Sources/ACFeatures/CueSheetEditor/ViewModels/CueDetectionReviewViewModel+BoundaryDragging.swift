import ACCore
import ACDesignSystem
import Foundation

/// Boundary-marker dragging (SPEC.md §4.19, "Boundary markers: contiguous
/// vs. non-contiguous") with real ⌘Z/⌘⇧Z undo/redo — split into its own file
/// purely to keep `CueDetectionReviewViewModel` under this project's
/// type-body-length lint limit, the same pattern `+Delete.swift`/
/// `+SplitMergeUndo.swift` already establish.
///
/// **Reverses this feature's original design** (SPEC.md §4.19 used to read:
/// "Not registered with `UndoManager`. Like the pre-existing single-marker
/// reposition drag..., a boundary drag — including the atomic two-cue case —
/// is fully, losslessly reversible by dragging again; nothing is discarded
/// the way merge's field-combination is."). That reasoning was technically
/// correct but didn't match how users actually expect ⌘Z to behave in this
/// view — a universal, consistent undo across every mutating gesture, not
/// one that works for delete/split/merge but not dragging. See
/// `docs/DECISIONS.md` (2026-09-14) for the full reversal record.
///
/// **Same registration-timing rule as `+Delete.swift`/`+SplitMergeUndo.swift`,
/// for the same reason:** the next inverse action is registered
/// synchronously, before the async I/O it belongs to starts.
///
/// **`moveBoundary`'s own branch decision (one cue vs. an atomic two-cue
/// push-through) is only knowable for certain *after* its write completes**
/// — it's re-derived fresh from live repository state at call time (this
/// type's own architecture, `UpdateCueUseCase+MoveBoundary.swift`), not a
/// stored flag. Synchronous pre-registration can't wait for that. Resolved
/// by `UpdateCueUseCase.planBoundaryMove(cues:marker:toOffsetSeconds:fileEndSeconds:)`
/// — the same pure planning logic `moveBoundary` itself runs internally,
/// exposed so this ViewModel can predict, from its own already-live `cues`
/// snapshot, exactly which cue(s) are about to be touched and capture their
/// pre-drag values *before* ever calling the real async Use Case. Those
/// captured values (not a fresh re-derivation) are what thread through every
/// subsequent undo/redo cycle — the same "capture once, replay the same
/// snapshot on every toggle" shape `+Delete.swift`/`+SplitMergeUndo.swift`
/// already use.
public extension CueDetectionReviewViewModel {
    /// The waveform's drag-to-reposition gesture now targets either edge of
    /// a cue — `WaveformBoundaryMarker`'s plain cue-index is translated to a
    /// real `Cue.ID` here, at the point it crosses back into `ACCore`, the
    /// same adapter-at-the-edge translation `mergeRequested` already
    /// performs for its own marker index.
    func boundaryDragged(marker: WaveformBoundaryMarker, toSeconds seconds: Double, undoManager: UndoManager?) {
        let index = Self.cueIndex(for: marker)
        guard cues.indices.contains(index) else { return }
        let cueID = cues[index].id
        let boundaryMarkerKind: BoundaryMarkerKind = switch marker {
        case .start: .start(cueID)
        case .end: .end(cueID)
        }
        // Predicted from the live `cues` snapshot already driving what the
        // user sees, before `moveBoundary`'s own real, authoritative write —
        // see this file's doc comment above.
        let plan = UpdateCueUseCase.planBoundaryMove(
            cues: cues,
            marker: boundaryMarkerKind,
            toOffsetSeconds: seconds,
            fileEndSeconds: fileDurationSeconds
        )
        let preDragSnapshots: [Cue.ID: Cue] = Dictionary(uniqueKeysWithValues: plan.compactMap { entry in
            cues.indices.contains(entry.index) ? (entry.cue.id, cues[entry.index]) : nil
        })
        performMoveBoundary(
            marker: boundaryMarkerKind,
            toOffsetSeconds: seconds,
            preDragSnapshots: preDragSnapshots,
            undoManager: undoManager
        )
    }

    private func performMoveBoundary(
        marker: BoundaryMarkerKind,
        toOffsetSeconds: Double,
        preDragSnapshots: [Cue.ID: Cue],
        undoManager: UndoManager?
    ) {
        registerUndoForBoundaryRestore(
            marker: marker,
            toOffsetSeconds: toOffsetSeconds,
            preDragSnapshots: preDragSnapshots,
            undoManager: undoManager
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                try await updateCueUseCase.moveBoundary(
                    projectID: projectID,
                    marker: marker,
                    toOffsetSeconds: toOffsetSeconds
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func registerUndoForBoundaryRestore(
        marker: BoundaryMarkerKind,
        toOffsetSeconds: Double,
        preDragSnapshots: [Cue.ID: Cue],
        undoManager: UndoManager?
    ) {
        // No cue(s) resolved (shouldn't happen given the caller's own
        // `cues.indices.contains(index)` guard) — mirrors split/merge's own
        // "don't register a bogus undo for a mutation that didn't really
        // happen" discipline; the write itself still proceeds regardless,
        // matching this gesture's pre-existing unconditional-write behavior.
        guard let undoManager, !preDragSnapshots.isEmpty else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            viewModel.performBoundaryRestore(
                marker: marker,
                toOffsetSeconds: toOffsetSeconds,
                preDragSnapshots: preDragSnapshots,
                undoManager: undoManager
            )
        }
        undoManager.setActionName("Move Boundary")
    }

    /// Boundary-drag's inverse — one cue for an independent move, two for an
    /// atomic contiguous push-through, matching however many `preDragSnapshots`
    /// holds (captured once, at the original drag). The two-cue case writes
    /// back non-atomically (two sequential `edit` calls) but each is
    /// independently exact, so the visible end state is identical to a true
    /// atomic restore either way — the same two-sequential-writes shape
    /// merge's own undo already uses for its own two affected cues
    /// (`+SplitMergeUndo.swift`'s `performUnmerge`).
    ///
    /// **Known, deliberate exception, same as merge's own undo:** `edit`
    /// always reclassifies its result to `.manual` (SPEC.md §4.3), so a
    /// pre-drag `source` of anything other than `.manual` doesn't come back
    /// exactly — see SPEC.md §4.19's "Undo losslessness" note.
    private func performBoundaryRestore(
        marker: BoundaryMarkerKind,
        toOffsetSeconds: Double,
        preDragSnapshots: [Cue.ID: Cue],
        undoManager: UndoManager?
    ) {
        registerUndoForMoveBoundary(
            marker: marker,
            toOffsetSeconds: toOffsetSeconds,
            preDragSnapshots: preDragSnapshots,
            undoManager: undoManager
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                for (cueID, snapshot) in preDragSnapshots {
                    try await updateCueUseCase.edit(projectID: projectID, cueID: cueID) { _ in snapshot }
                }
            } catch {
                errorMessage = "Couldn't undo the boundary move."
            }
        }
    }

    private func registerUndoForMoveBoundary(
        marker: BoundaryMarkerKind,
        toOffsetSeconds: Double,
        preDragSnapshots: [Cue.ID: Cue],
        undoManager: UndoManager?
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            viewModel.performMoveBoundary(
                marker: marker,
                toOffsetSeconds: toOffsetSeconds,
                preDragSnapshots: preDragSnapshots,
                undoManager: undoManager
            )
        }
        undoManager.setActionName("Move Boundary")
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
