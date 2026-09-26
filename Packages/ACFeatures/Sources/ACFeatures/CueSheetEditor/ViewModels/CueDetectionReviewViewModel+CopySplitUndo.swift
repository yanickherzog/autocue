import ACCore
import Foundation

/// "Copy Split to Other Cues" (`CueRowDetailView`, `ROADMAP.md` D10) with
/// real ⌘Z/⌘⇧Z undo/redo — split into its own file for the same
/// type-body-length-limit reason `+Delete.swift`/`+SplitMergeUndo.swift`
/// already are, and following their exact registration-timing rule: the
/// next inverse action is registered synchronously, before the async I/O it
/// belongs to starts, so `UndoManager` correctly alternates the
/// registration onto the *redo* stack when this code is itself running as
/// the target of a previous undo/redo.
///
/// **One `UndoManager.registerUndo` call for the whole bulk copy, not one
/// per affected cue** — per direct instruction: a single ⌘Z must restore
/// every cue this touched together, the same snapshot-based-restore shape
/// merge's own undo already uses (`+SplitMergeUndo.swift`'s
/// `performUnmerge`), scaled from one cue to every cue in the project.
extension CueDetectionReviewViewModel {
    /// `CueRowDetailView`'s "Copy Split to Other Cues" button. `rightHolders`
    /// is the sheet's own current local buffer — including any edits not yet
    /// committed via "Done" — since from the user's perspective that's
    /// "this cue's" right-holder list at the moment the button is pressed.
    public func copySplitToOtherCuesRequested(rightHolders: [CueRightHolder], undoManager: UndoManager?) {
        let snapshot = Dictionary(uniqueKeysWithValues: cues.map { ($0.id, $0.rightHolders) })
        performCopySplit(rightHolders: rightHolders, snapshot: snapshot, undoManager: undoManager)
    }

    private func performCopySplit(
        rightHolders: [CueRightHolder],
        snapshot: [Cue.ID: [CueRightHolder]],
        undoManager: UndoManager?
    ) {
        registerUndoForRestoreSplit(rightHolders: rightHolders, snapshot: snapshot, undoManager: undoManager)
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await updateCueUseCase.copyRightHolders(projectID: projectID, rightHolders: rightHolders)
            } catch {
                errorMessage = "Couldn't copy the right-holder split to the other cues."
            }
        }
    }

    private func registerUndoForRestoreSplit(
        rightHolders: [CueRightHolder],
        snapshot: [Cue.ID: [CueRightHolder]],
        undoManager: UndoManager?
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            viewModel.performRestoreSplit(rightHolders: rightHolders, snapshot: snapshot, undoManager: undoManager)
        }
        undoManager.setActionName("Copy Split to All Cues")
    }

    /// The inverse — restores every cue named in `snapshot` to its exact
    /// pre-copy `rightHolders` list, in one atomic write. `rightHolders` is
    /// threaded through only so a subsequent ⌘⇧Z can re-run the same copy.
    private func performRestoreSplit(
        rightHolders: [CueRightHolder],
        snapshot: [Cue.ID: [CueRightHolder]],
        undoManager: UndoManager?
    ) {
        registerUndoForCopySplit(rightHolders: rightHolders, snapshot: snapshot, undoManager: undoManager)
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await updateCueUseCase.restoreRightHolders(projectID: projectID, snapshot: snapshot)
            } catch {
                errorMessage = "Couldn't undo the right-holder split copy."
            }
        }
    }

    private func registerUndoForCopySplit(
        rightHolders: [CueRightHolder],
        snapshot: [Cue.ID: [CueRightHolder]],
        undoManager: UndoManager?
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            viewModel.performCopySplit(rightHolders: rightHolders, snapshot: snapshot, undoManager: undoManager)
        }
        undoManager.setActionName("Copy Split to All Cues")
    }
}
