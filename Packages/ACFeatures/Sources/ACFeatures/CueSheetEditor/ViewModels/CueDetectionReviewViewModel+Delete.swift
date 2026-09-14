import ACCore
import Foundation

/// Delete (SPEC.md §4.18, §4.19 capability 2) with real ⌘Z/⌘⇧Z undo/redo —
/// split into its own file purely to stay under this project's
/// type-body-length lint limit, same reason `+BoundaryDragging.swift`/
/// `+ClearImportedAudio.swift` are already separate.
///
/// **Not the only structural mutation with real undo support any more** —
/// `splitRequested`/`mergeRequested` (`+SplitMergeUndo.swift`) gained the
/// same real ⌘Z/⌘⇧Z support this file established first, closing the
/// spec/implementation gap `docs/REVIEW.md` had flagged as a known,
/// accepted follow-up. This file's own registration-timing discipline
/// (below) is what that later file follows too.
///
/// **The next inverse action is registered synchronously, *before* the async
/// I/O it belongs to even starts — not after that I/O confirms success.**
/// This looks backwards at first, but it's required, not a shortcut:
/// `UndoManager` only correctly alternates a `registerUndo` call onto its
/// *redo* stack when that call happens synchronously, nested inside the
/// currently-executing undo/redo closure (i.e. while `isUndoing`/
/// `isRedoing` is still `true`). Every operation here is `async` (real
/// repository I/O), so registering the next inverse only after `await`ing
/// that I/O means the registration happens *after* `undo()`/`redo()` has
/// already returned and reset that flag — the call silently lands back on
/// the *undo* stack instead, breaking ⌘⇧Z (confirmed by a real, reproduced
/// test failure during this feature's own test-writing, not a hypothetical:
/// `undoManager.redo()` after `undoManager.undo()` did nothing, because the
/// "redo" action had actually been queued as a second "undo"). Registering
/// up front is the standard, accepted resolution for this exact class of
/// bug — it trades a vanishingly rare "registered an inverse for an I/O
/// that then fails" inconsistency (already handled no worse than any other
/// failed write here: `errorMessage` surfaces it) for correct, indefinite
/// undo/redo toggling in the overwhelmingly common case.
extension CueDetectionReviewViewModel {
    /// The ✕ button's action (`CueTableView`'s row) — `index` is the row's
    /// position in `cues` at the moment of the click.
    public func deleteCue(at index: Int, undoManager: UndoManager?) {
        guard cues.indices.contains(index) else { return }
        performDelete(cue: cues[index], atIndex: index, undoManager: undoManager)
    }

    /// `cue`'s full field values must be captured by the caller *before*
    /// this runs — once `updateCueUseCase.delete` returns, the cue is gone
    /// from the live `cues` snapshot, so this is the last point they're
    /// available to hand to the inverse (reinsert) action.
    private func performDelete(cue: Cue, atIndex index: Int, undoManager: UndoManager?) {
        registerUndoForReinsert(cue: cue, atIndex: index, undoManager: undoManager)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await updateCueUseCase.delete(projectID: projectID, cueID: cue.id)
            } catch {
                errorMessage = "Couldn't delete the cue."
            }
        }
    }

    private func registerUndoForReinsert(cue: Cue, atIndex index: Int, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            viewModel.performReinsert(cue: cue, atIndex: index, undoManager: undoManager)
        }
        undoManager.setActionName("Delete Cue")
    }

    private func performReinsert(cue: Cue, atIndex index: Int, undoManager: UndoManager?) {
        registerUndoForDelete(cue: cue, atIndex: index, undoManager: undoManager)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await updateCueUseCase.insertForUndo(projectID: projectID, cue: cue, atIndex: index)
            } catch {
                errorMessage = "Couldn't restore the deleted cue."
            }
        }
    }

    private func registerUndoForDelete(cue: Cue, atIndex index: Int, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            viewModel.performDelete(cue: cue, atIndex: index, undoManager: undoManager)
        }
        undoManager.setActionName("Delete Cue")
    }
}
