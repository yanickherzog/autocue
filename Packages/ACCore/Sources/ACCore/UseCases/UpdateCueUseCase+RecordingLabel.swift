import Foundation

/// Bulk recording-label mutations spanning every `Cue` in a `Project` at
/// once — "Copy Label to Other Cues" (`CueRecordingInfoSheet`, SPEC.md
/// §4.26), mirroring `+RightHolders.swift`'s "Copy Split to Other Cues"
/// exactly: same atomic-write requirement, same reclassification rule, same
/// snapshot-based undo shape (`CueDetectionReviewViewModel+CopyLabelUndo.swift`).
///
/// **`recordingISRC` is deliberately never touched by either method.** An
/// ISRC identifies one specific master recording — a fact about *that* cue's
/// own usage, not something that makes sense to propagate onto an unrelated
/// cue just because the two happen to share a record label. Only
/// `recordingLabel`/`recordingLabelNumber` are copied/restored; every other
/// field, `recordingISRC` included, is carried through from each cue
/// unchanged.
public extension UpdateCueUseCase {
    /// Writes `recordingLabel`/`recordingLabelNumber` onto every `Cue` in
    /// the project, including the source cue itself — harmless there (the
    /// caller passes exactly the values it wants that cue to end up with
    /// too), and this is also what commits the source cue's own
    /// not-yet-saved sheet edits in the same atomic write.
    @discardableResult
    func copyRecordingLabel(
        projectID: Project.ID,
        recordingLabel: Party?,
        recordingLabelNumber: String?
    ) async throws -> [Cue] {
        let updated = try await projectRepository.update(id: projectID) { project in
            let cues = project.cues.map {
                $0.replacingRecordingLabel(recordingLabel, recordingLabelNumber: recordingLabelNumber)
            }
            return project.replacingCues(cues)
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        return updated.cues
    }

    /// Copy's inverse — restores each cue named in `snapshot` to its exact
    /// prior `recordingLabel`/`recordingLabelNumber`, in one atomic write. A
    /// cue absent from `snapshot` is left untouched rather than trapping (in
    /// practice this never happens: the ViewModel snapshots every cue that
    /// existed at copy time).
    @discardableResult
    func restoreRecordingLabel(
        projectID: Project.ID,
        snapshot: [Cue.ID: RecordingLabelSnapshot]
    ) async throws -> [Cue] {
        let updated = try await projectRepository.update(id: projectID) { project in
            let cues = project.cues.map { cue -> Cue in
                guard let original = snapshot[cue.id] else { return cue }
                return cue.replacingRecordingLabel(
                    original.recordingLabel,
                    recordingLabelNumber: original.recordingLabelNumber
                )
            }
            return project.replacingCues(cues)
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        return updated.cues
    }
}

/// One cue's pre-copy `recordingLabel`/`recordingLabelNumber` pair, captured
/// for `restoreRecordingLabel`'s snapshot-based undo. A plain struct, not a
/// bare tuple, so the snapshot dictionary's value type has a name at every
/// call site (`CueDetectionReviewViewModel+CopyLabelUndo.swift`).
public struct RecordingLabelSnapshot: Equatable, Sendable {
    public let recordingLabel: Party?
    public let recordingLabelNumber: String?

    public init(recordingLabel: Party?, recordingLabelNumber: String?) {
        self.recordingLabel = recordingLabel
        self.recordingLabelNumber = recordingLabelNumber
    }
}

private extension Cue {
    func replacingRecordingLabel(_ recordingLabel: Party?, recordingLabelNumber: String?) -> Cue {
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
