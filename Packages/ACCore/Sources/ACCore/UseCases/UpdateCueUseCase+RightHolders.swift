import Foundation

/// Bulk right-holder mutations spanning every `Cue` in a `Project` at once —
/// "Copy Split to Other Cues" (`ROADMAP.md` D10, `CueRowDetailView`). Split
/// into its own file for the same one-clear-operation-per-extension-file
/// convention `+AddReorder.swift`/`+MoveBoundary.swift` already establish.
///
/// **Both methods write every project cue in a single atomic
/// `ProjectRepository.update(id:transform:)` call** — required for the
/// calling ViewModel's undo/redo to be a single, all-or-nothing action
/// (`CueDetectionReviewViewModel+CopySplitUndo.swift`): one ⌘Z must restore
/// every cue this touched, not require undoing them one at a time.
///
/// **Both reclassify every touched cue as `.manual`** — consistent with
/// `edit()`'s own unconditional reclassification rule (SPEC.md §4.3):
/// editing `rightHolders` is exactly the kind of field edit that rule
/// already covers, whether it happens through this bulk path or the
/// single-cue `edit()` path. `restoreRightHolders` (the undo side) does the
/// same, matching the one accepted, already-documented asymmetry merge's
/// own undo established (`+SplitMergeUndo.swift`'s `performUnmerge` doc
/// comment): a restore is no less exact than the state the forward
/// operation itself produced, and `source` was never going back to
/// `.detectedFromAudio` after either direction touched it.
public extension UpdateCueUseCase {
    /// Writes `rightHolders` onto every `Cue` in the project, including the
    /// source cue itself — harmless there (the caller passes exactly the
    /// list it wants that cue to end up with too), and this is also what
    /// commits the source cue's own not-yet-saved sheet edits in the same
    /// atomic write, without a separate call first.
    @discardableResult
    func copyRightHolders(projectID: Project.ID, rightHolders: [CueRightHolder]) async throws -> [Cue] {
        let updated = try await projectRepository.update(id: projectID) { project in
            let cues = project.cues.map { $0.replacingRightHolders(rightHolders) }
            return project.replacingCues(cues)
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        return updated.cues
    }

    /// Copy's inverse — restores each cue named in `snapshot` to its exact
    /// prior `rightHolders` list, in one atomic write. A cue absent from
    /// `snapshot` is left untouched rather than trapping (in practice this
    /// never happens: the ViewModel snapshots every cue that existed at
    /// copy time).
    @discardableResult
    func restoreRightHolders(
        projectID: Project.ID,
        snapshot: [Cue.ID: [CueRightHolder]]
    ) async throws -> [Cue] {
        let updated = try await projectRepository.update(id: projectID) { project in
            let cues = project.cues.map { cue -> Cue in
                guard let original = snapshot[cue.id] else { return cue }
                return cue.replacingRightHolders(original)
            }
            return project.replacingCues(cues)
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        return updated.cues
    }
}

private extension Cue {
    func replacingRightHolders(_ rightHolders: [CueRightHolder]) -> Cue {
        Cue(
            id: id,
            title: title,
            workNumber: workNumber,
            duration: duration,
            rightHolders: rightHolders,
            isArrangementOfProtectedOriginal: isArrangementOfProtectedOriginal,
            source: .manual,
            startTimecode: startTimecode,
            notes: notes,
            recordingLabel: recordingLabel,
            recordingLabelNumber: recordingLabelNumber,
            recordingISRC: recordingISRC
        )
    }
}
