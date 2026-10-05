import ACCore
import Foundation

/// "Copy Label to Other Cues" (`CueRecordingInfoSheet`, SPEC.md §4.26) with
/// real ⌘Z/⌘⇧Z undo/redo — mirrors `+CopySplitUndo.swift` exactly: one
/// `UndoManager.registerUndo` call for the whole bulk copy, registered
/// synchronously before the async write it belongs to, so `UndoManager`
/// correctly alternates the registration onto the *redo* stack when this
/// code is itself running as the target of a previous undo/redo.
///
/// **`recordingISRC` is never part of this copy** — see
/// `UpdateCueUseCase+RecordingLabel.swift`'s own doc comment for why; this
/// file only ever threads `recordingLabel`/`recordingLabelNumber` through.
extension CueDetectionReviewViewModel {
    /// `CueRecordingInfoSheet`'s "Copy Label to Other Cues" button.
    /// `recordingLabel`/`recordingLabelNumber` are the sheet's own current
    /// values at the moment the button is pressed.
    public func copyRecordingLabelToOtherCuesRequested(
        recordingLabel: Party?,
        recordingLabelNumber: String?,
        undoManager: UndoManager?
    ) {
        let snapshot = Dictionary(uniqueKeysWithValues: cues.map {
            (
                $0.id,
                RecordingLabelSnapshot(recordingLabel: $0.recordingLabel, recordingLabelNumber: $0.recordingLabelNumber)
            )
        })
        performCopyRecordingLabel(
            recordingLabel: recordingLabel,
            recordingLabelNumber: recordingLabelNumber,
            snapshot: snapshot,
            undoManager: undoManager
        )
    }

    private func performCopyRecordingLabel(
        recordingLabel: Party?,
        recordingLabelNumber: String?,
        snapshot: [Cue.ID: RecordingLabelSnapshot],
        undoManager: UndoManager?
    ) {
        registerUndoForRestoreRecordingLabel(
            recordingLabel: recordingLabel,
            recordingLabelNumber: recordingLabelNumber,
            snapshot: snapshot,
            undoManager: undoManager
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await updateCueUseCase.copyRecordingLabel(
                    projectID: projectID,
                    recordingLabel: recordingLabel,
                    recordingLabelNumber: recordingLabelNumber
                )
            } catch {
                errorMessage = "Couldn't copy the label to the other cues."
            }
        }
    }

    private func registerUndoForRestoreRecordingLabel(
        recordingLabel: Party?,
        recordingLabelNumber: String?,
        snapshot: [Cue.ID: RecordingLabelSnapshot],
        undoManager: UndoManager?
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            viewModel.performRestoreRecordingLabel(
                recordingLabel: recordingLabel,
                recordingLabelNumber: recordingLabelNumber,
                snapshot: snapshot,
                undoManager: undoManager
            )
        }
        undoManager.setActionName("Copy Label to All Cues")
    }

    /// The inverse — restores every cue named in `snapshot` to its exact
    /// pre-copy `recordingLabel`/`recordingLabelNumber`, in one atomic
    /// write. The forward values are threaded through only so a subsequent
    /// ⌘⇧Z can re-run the same copy.
    private func performRestoreRecordingLabel(
        recordingLabel: Party?,
        recordingLabelNumber: String?,
        snapshot: [Cue.ID: RecordingLabelSnapshot],
        undoManager: UndoManager?
    ) {
        registerUndoForCopyRecordingLabel(
            recordingLabel: recordingLabel,
            recordingLabelNumber: recordingLabelNumber,
            snapshot: snapshot,
            undoManager: undoManager
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await updateCueUseCase.restoreRecordingLabel(projectID: projectID, snapshot: snapshot)
            } catch {
                errorMessage = "Couldn't undo the label copy."
            }
        }
    }

    private func registerUndoForCopyRecordingLabel(
        recordingLabel: Party?,
        recordingLabelNumber: String?,
        snapshot: [Cue.ID: RecordingLabelSnapshot],
        undoManager: UndoManager?
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            viewModel.performCopyRecordingLabel(
                recordingLabel: recordingLabel,
                recordingLabelNumber: recordingLabelNumber,
                snapshot: snapshot,
                undoManager: undoManager
            )
        }
        undoManager.setActionName("Copy Label to All Cues")
    }
}
