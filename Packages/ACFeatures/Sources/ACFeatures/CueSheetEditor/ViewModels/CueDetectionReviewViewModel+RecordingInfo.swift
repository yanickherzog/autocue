import ACCore
import Foundation

/// Field-level edits reachable from `CueTableView`'s "Label" column
/// (`CueRecordingInfoSheet`) — `Cue.recordingLabel`/`.recordingLabelNumber`/
/// `.recordingISRC` (SPEC.md §4.3). Split into its own file for the same
/// type-body-length-limit reason every other `CueDetectionReviewViewModel`
/// extension already is.
///
/// **Label selection writes immediately; Label-Nr./ISRC-Nr. are debounced —
/// the same split `+RowDetail.swift`'s title field vs. `+RightHolders.swift`'s
/// one-shot commit already establish.** A picker selection is a discrete,
/// complete action with nothing further to type, so it writes through at
/// once; the two text fields are continuous per-keystroke edits, the case
/// SPEC.md §4.18 reserves debouncing for. Neither gets `UndoManager`
/// registration — this is a field-level edit, not one of the five structural
/// mutations (§4.18/§4.19), matching every other field edit in this file's
/// sibling extensions.
public extension CueDetectionReviewViewModel {
    // MARK: - Label (picker selection — immediate)

    func recordingLabelSelected(cueID: Cue.ID, party: Party) async {
        await saveRecordingLabel(cueID: cueID, recordingLabel: party)
    }

    func recordingLabelCleared(cueID: Cue.ID) async {
        await saveRecordingLabel(cueID: cueID, recordingLabel: nil)
    }

    private func saveRecordingLabel(cueID: Cue.ID, recordingLabel: Party?) async {
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
                    startTimecode: cue.startTimecode,
                    notes: cue.notes,
                    recordingLabel: recordingLabel,
                    recordingLabelNumber: cue.recordingLabelNumber,
                    recordingISRC: cue.recordingISRC
                )
            }
        } catch {
            errorMessage = "Couldn't save the recording label."
        }
    }

    // MARK: - Label-Nr. (debounced)

    func recordingLabelNumberChanged(cueID: Cue.ID, newValue: String) {
        recordingLabelNumberEditDebounceTasks[cueID]?.cancel()
        recordingLabelNumberEditDebounceTasks[cueID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.fieldEditDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.saveRecordingLabelNumber(cueID: cueID, newValue: newValue)
        }
    }

    private func saveRecordingLabelNumber(cueID: Cue.ID, newValue: String) async {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    startTimecode: cue.startTimecode,
                    notes: cue.notes,
                    recordingLabel: cue.recordingLabel,
                    recordingLabelNumber: trimmed.isEmpty ? nil : trimmed,
                    recordingISRC: cue.recordingISRC
                )
            }
        } catch {
            errorMessage = "Couldn't save the label number."
        }
    }

    // MARK: - ISRC-Nr. (debounced)

    func recordingISRCChanged(cueID: Cue.ID, newValue: String) {
        recordingISRCEditDebounceTasks[cueID]?.cancel()
        recordingISRCEditDebounceTasks[cueID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.fieldEditDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.saveRecordingISRC(cueID: cueID, newValue: newValue)
        }
    }

    private func saveRecordingISRC(cueID: Cue.ID, newValue: String) async {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    startTimecode: cue.startTimecode,
                    notes: cue.notes,
                    recordingLabel: cue.recordingLabel,
                    recordingLabelNumber: cue.recordingLabelNumber,
                    recordingISRC: trimmed.isEmpty ? nil : trimmed
                )
            }
        } catch {
            errorMessage = "Couldn't save the ISRC number."
        }
    }
}
