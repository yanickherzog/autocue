import ACCore
import Foundation

/// Per-cue right-holder commit (`ROADMAP.md` D10, second round) — split into
/// its own file for the same type-body-length-limit reason every other
/// `CueDetectionReviewViewModel` extension already is.
///
/// **Editing itself is no longer live/per-keystroke or ViewModel-owned.**
/// The original version of this file had one debounced ViewModel method per
/// field (add/remove/role/party/attachment/share), each writing through
/// `UpdateCueUseCase.edit` independently, mid-edit, while the sheet was
/// still open. That design is what let a live "does this pool still sum to
/// ≤100%" check — briefly present in `CueRightHolderEditorView` at the same
/// Deliverable, since removed — clamp/reject a keystroke the moment a pool
/// was already at or over 100%, since every keystroke was its own
/// independent round trip racing the next one. Per direct instruction, the
/// whole editing session is now a single local, freely-editable buffer
/// (`CueRowDetailView`'s own `@State`) with no clamping and no round trip
/// per keystroke; this file's only remaining job is committing that buffer
/// in one write when "Done" is pressed. `ValidateCueRightHolderSharesUseCase`
/// runs once at that same point, purely to decide whether to show a
/// non-blocking warning — never to gate the commit itself.
public extension CueDetectionReviewViewModel {
    /// `CueRowDetailView`'s "Done" button — one write for the whole sheet's
    /// worth of edits, not one per field. `rightHolders` is whatever the
    /// sheet's own local buffer holds at the moment of the tap.
    func commitRightHolderEdits(cueID: Cue.ID, rightHolders: [CueRightHolder]) async {
        do {
            try await updateCueUseCase.edit(projectID: projectID, cueID: cueID) { cue in
                Cue(
                    id: cue.id,
                    title: cue.title,
                    workNumber: cue.workNumber,
                    duration: cue.duration,
                    rightHolders: rightHolders,
                    isArrangementOfProtectedOriginal: cue.isArrangementOfProtectedOriginal,
                    source: cue.source,
                    startTimecode: cue.startTimecode,
                    notes: cue.notes
                )
            }
        } catch {
            errorMessage = "Couldn't save the right-holder changes."
        }
    }
}
