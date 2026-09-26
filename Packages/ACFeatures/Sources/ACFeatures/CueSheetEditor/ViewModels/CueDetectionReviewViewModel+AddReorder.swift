import ACCore
import Foundation

/// "+ Add Cue" (SPEC.md §4.19 capability 1) and reorder — `ROADMAP.md`
/// D10/T10.1's remaining scope on top of the D9 pull-forward, split into its
/// own file for the same type-body-length-limit reason `+Delete.swift`/
/// `+SplitMergeUndo.swift`/`+BoundaryDragging.swift` already are.
///
/// **Same registration-timing rule as those files, for the same reason:**
/// the next inverse action is registered synchronously, before the async I/O
/// it belongs to starts.
///
/// **Reorder's own undo is a plain reverse move, not a full snapshot
/// restore** — unlike merge/split, reordering never touches any `Cue`
/// field (SPEC.md §4.1: order isn't stored on `Cue` at all), so there's
/// nothing lossy to snapshot; undoing "moved to index 2" is simply "move
/// back to index 0."
extension CueDetectionReviewViewModel {
    // MARK: - Add

    /// "+ Add Cue" button's action — appends a fresh cue with
    /// `UpdateCueUseCase.add`'s pinned defaults at the end of `cues`.
    public func addCue(undoManager: UndoManager?) {
        performAdd(cueID: UUID(), undoManager: undoManager)
    }

    private func performAdd(cueID: Cue.ID, undoManager: UndoManager?) {
        registerUndoForRemoveAdded(cueID: cueID, undoManager: undoManager)
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await updateCueUseCase.add(projectID: projectID, cueID: cueID)
            } catch {
                errorMessage = "Couldn't add a new cue."
            }
        }
    }

    private func registerUndoForRemoveAdded(cueID: Cue.ID, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            viewModel.performRemoveAdded(cueID: cueID, undoManager: undoManager)
        }
        undoManager.setActionName("Add Cue")
    }

    /// Add's inverse — captures the cue's *current* field values and index
    /// from the live `cues` snapshot immediately before removing it, not the
    /// blank values it was created with: the user may already have edited
    /// its title/timecode/right-holders by the time undo is invoked, and
    /// redo (below) must restore exactly that, not a fresh blank cue. Same
    /// "capture just before removing" discipline `+Delete.swift`'s
    /// `deleteCue(at:)` already establishes for the ✕ button.
    private func performRemoveAdded(cueID: Cue.ID, undoManager: UndoManager?) {
        guard let index = cues.firstIndex(where: { $0.id == cueID }) else { return }
        let cue = cues[index]
        registerUndoForReaddRemoved(cue: cue, atIndex: index, undoManager: undoManager)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await updateCueUseCase.delete(projectID: projectID, cueID: cueID)
            } catch {
                errorMessage = "Couldn't undo adding the cue."
            }
        }
    }

    private func registerUndoForReaddRemoved(cue: Cue, atIndex index: Int, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            viewModel.performReaddRemoved(cue: cue, atIndex: index, undoManager: undoManager)
        }
        undoManager.setActionName("Add Cue")
    }

    private func performReaddRemoved(cue: Cue, atIndex index: Int, undoManager: UndoManager?) {
        registerUndoForRemoveAdded(cueID: cue.id, undoManager: undoManager)
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await updateCueUseCase.insertForUndo(projectID: projectID, cue: cue, atIndex: index)
            } catch {
                errorMessage = "Couldn't redo adding the cue."
            }
        }
    }

    // MARK: - Reorder

    /// `CueTableView`'s ↑/↓ buttons' action — `index` is the row's current
    /// position in `cues`; `direction` decides whether it targets `index - 1`
    /// or `index + 1`. A no-op at either end of the list (the buttons are
    /// already `disabled` there per `CueTableRow.canMoveUp`/`.canMoveDown`,
    /// but this guards the ViewModel call directly too, independent of the
    /// View correctly disabling them).
    public func moveCue(at index: Int, direction: CueReorderDirection, undoManager: UndoManager?) {
        guard cues.indices.contains(index) else { return }
        let targetIndex = index + direction.offset
        guard cues.indices.contains(targetIndex) else { return }
        let cueID = cues[index].id
        performReorder(cueID: cueID, toIndex: targetIndex, returnIndex: index, undoManager: undoManager)
    }

    /// `toIndex`/`returnIndex` are exactly symmetric: performing this moves
    /// `cueID` to `toIndex` and registers an inverse that performs the same
    /// operation with the two swapped — moving it back to `returnIndex`, and
    /// registering a further inverse that swaps them back again, and so on
    /// indefinitely through ⌘Z/⌘⇧Z.
    private func performReorder(cueID: Cue.ID, toIndex: Int, returnIndex: Int, undoManager: UndoManager?) {
        registerUndoForReorder(cueID: cueID, toIndex: returnIndex, returnIndex: toIndex, undoManager: undoManager)
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await updateCueUseCase.reorder(projectID: projectID, cueID: cueID, toIndex: toIndex)
            } catch {
                errorMessage = "Couldn't reorder cues."
            }
        }
    }

    private func registerUndoForReorder(cueID: Cue.ID, toIndex: Int, returnIndex: Int, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            viewModel.performReorder(cueID: cueID, toIndex: toIndex, returnIndex: returnIndex, undoManager: undoManager)
        }
        undoManager.setActionName("Reorder Cues")
    }
}

/// Which way `CueTableView`'s ↑/↓ buttons move a cue — a plain, domain-free
/// direction (not a raw `Bool`/`Int` offset at the call site) so
/// `CueDetectionReviewView`'s button actions read as "move up"/"move down,"
/// not an easy-to-transpose `+1`/`-1` at every call site.
public enum CueReorderDirection {
    case up
    case down

    var offset: Int {
        switch self {
        case .up: -1
        case .down: 1
        }
    }
}
