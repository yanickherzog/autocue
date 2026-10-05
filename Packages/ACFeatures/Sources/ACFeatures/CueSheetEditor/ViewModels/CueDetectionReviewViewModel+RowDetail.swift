import ACCore
import Foundation

/// Field-level edits reachable from `CueTableView`'s Title cell and
/// `CueRowDetailView`'s direct-timecode field (`ROADMAP.md` D10/T10.2,
/// SPEC.md §4.19 capability 3) — split into its own file for the same
/// type-body-length-limit reason every other `CueDetectionReviewViewModel`
/// extension already is.
///
/// **Debounced, not immediate — unlike `+AddReorder.swift`/`+Delete.swift`/
/// `+SplitMergeUndo.swift`.** These are continuous field-level edits (typing
/// a title, typing a timecode), the exact case SPEC.md §4.18 reserves
/// debouncing for; structural mutations (add/delete/reorder/split/merge)
/// write through immediately, per that same section. Neither gets
/// `UndoManager` registration, matching `SetupViewModel`'s own field edits —
/// SPEC.md never asks for undo on a plain field-level correction, only on
/// the five structural mutations (§4.18/§4.19).
extension CueDetectionReviewViewModel {
    // MARK: - Title

    /// `CueTableView`'s Title cell calls this on every keystroke — debounced
    /// per-`Cue.ID` (not one shared task) so editing one row's title never
    /// cancels another row's still-pending save.
    public func titleChanged(cueID: Cue.ID, newTitle: String) {
        titleEditDebounceTasks[cueID]?.cancel()
        titleEditDebounceTasks[cueID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.fieldEditDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.saveTitle(cueID: cueID, title: newTitle)
        }
    }

    private func saveTitle(cueID: Cue.ID, title: String) async {
        do {
            try await updateCueUseCase.edit(projectID: projectID, cueID: cueID) { cue in
                Cue(
                    id: cue.id,
                    title: title,
                    workNumber: cue.workNumber,
                    duration: cue.duration,
                    rightHolders: cue.rightHolders,
                    isArrangementOfProtectedOriginal: cue.isArrangementOfProtectedOriginal,
                    source: cue.source,
                    startTimecode: cue.startTimecode,
                    notes: cue.notes,
                    recordingLabel: cue.recordingLabel,
                    recordingLabelNumber: cue.recordingLabelNumber,
                    recordingISRC: cue.recordingISRC
                )
            }
        } catch {
            errorMessage = "Couldn't save the cue title."
        }
    }

    // MARK: - Direct timecode edit

    /// `CueRowDetailView`'s direct-edit timecode field — parsing/validation
    /// is entirely `Timecode.init?(components:frameRate:)`'s own existing,
    /// already-tested job (SPEC.md §4.9/§4.19); this method only decides
    /// what to do with a successfully-parsed value. `nil` (an invalid
    /// timecode, including an invalid drop-frame value) is a no-op — the
    /// field's own View keeps showing whatever the user typed until it
    /// either parses or is corrected, the same "leave `value` alone on an
    /// unparseable intermediate string" behavior `GhostDecimalField`
    /// establishes for shares.
    public func startTimecodeChanged(cueID: Cue.ID, newTimecode: Timecode?) {
        startTimecodeEditDebounceTasks[cueID]?.cancel()
        startTimecodeEditDebounceTasks[cueID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.fieldEditDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.saveStartTimecode(cueID: cueID, startTimecode: newTimecode)
        }
    }

    private func saveStartTimecode(cueID: Cue.ID, startTimecode: Timecode?) async {
        do {
            try await updateCueUseCase.edit(projectID: projectID, cueID: cueID) { cue in
                Cue(
                    id: cue.id,
                    title: cue.title,
                    workNumber: cue.workNumber,
                    duration: cue.duration,
                    rightHolders: cue.rightHolders,
                    isArrangementOfProtectedOriginal: cue.isArrangementOfProtectedOriginal,
                    source: cue.source,
                    startTimecode: startTimecode,
                    notes: cue.notes,
                    recordingLabel: cue.recordingLabel,
                    recordingLabelNumber: cue.recordingLabelNumber,
                    recordingISRC: cue.recordingISRC
                )
            }
        } catch {
            errorMessage = "Couldn't save the cue's timecode."
        }
    }
}
