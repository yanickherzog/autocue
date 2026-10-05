import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.Cue` (SPEC.md §4.3).
///
/// `order` is persistence-only — `Project.cues` is domain-ordered (display
/// order), but SwiftData gives no fetch-order guarantee for a to-many
/// relationship, so order must be stored explicitly here and restored by
/// `CueMapper` on read. The domain `Cue` type deliberately has no such field
/// (SPEC.md §4.1); this is exactly the kind of persistence-only detail that
/// must not leak back into `ACCore`.
@Model
final class CueEntity {
    var id: UUID
    var order: Int
    var title: String
    var workNumber: String?
    var durationSeconds: Double
    var isArrangementOfProtectedOriginal: Bool
    var source: String
    var startTimecodeOffsetSeconds: Double?
    var notes: String?
    /// `Cue.recordingLabel: Party?` — a `Person`/`Label` reference, not a
    /// copied name, mirroring `SetupEntity.declarantPartyKind`/`.declarantPartyID`
    /// exactly (`docs/DECISIONS.md`).
    var recordingLabelPartyKind: String?
    var recordingLabelPartyID: UUID?
    var recordingLabelNumber: String?
    var recordingISRC: String?

    var project: ProjectEntity?
    @Relationship(deleteRule: .cascade, inverse: \CueRightHolderEntity.cue) var rightHolders: [CueRightHolderEntity]

    init(
        id: UUID,
        order: Int,
        title: String,
        workNumber: String?,
        durationSeconds: Double,
        isArrangementOfProtectedOriginal: Bool,
        source: String,
        startTimecodeOffsetSeconds: Double?,
        notes: String?,
        recordingLabelPartyKind: String?,
        recordingLabelPartyID: UUID?,
        recordingLabelNumber: String?,
        recordingISRC: String?
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.workNumber = workNumber
        self.durationSeconds = durationSeconds
        self.isArrangementOfProtectedOriginal = isArrangementOfProtectedOriginal
        self.source = source
        self.startTimecodeOffsetSeconds = startTimecodeOffsetSeconds
        self.notes = notes
        self.recordingLabelPartyKind = recordingLabelPartyKind
        self.recordingLabelPartyID = recordingLabelPartyID
        self.recordingLabelNumber = recordingLabelNumber
        self.recordingISRC = recordingISRC
        project = nil
        rightHolders = []
    }
}
