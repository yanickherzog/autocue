import Foundation

/// One SUISA "musical work" entry — many per `Project`. Display order lives on
/// `Project.cues` (an ordered `[Cue]`), not stored as a field here (SPEC.md
/// §4.1, §4.3).
///
/// **`recordingLabel`/`recordingLabelNumber`/`recordingISRC`** (SPEC.md §4.3,
/// added `ROADMAP.md` D11 planning, 2026-09-27): a licensed/pre-existing
/// recording's record label, catalog number, and ISRC (International
/// Standard Recording Code) — real-world evidence for these came from a
/// production using a licensed third-party track, distinct from the
/// production's own compositions. Deliberately on `Cue`, not
/// `CueRightHolder`: an ISRC identifies one specific master recording — a
/// fact about the work as used in the production, not about any one
/// person/label's role on it — the same reasoning that keeps
/// `isArrangementOfProtectedOriginal` here rather than on a right-holder row.
/// All three blank for the production's own compositions, the common case —
/// the same "blank unless relevant" pattern `Setup.otherProductionTypeDescription`/
/// `.isanNumber` already establish, with no separate boolean flag needed:
/// presence of a value is itself the signal. App-internal/cue-sheet-only —
/// confirmed absent from the literal SUISA WA Film form (`docs/DECISIONS.md`,
/// 2026-09-27); rendered on the cue sheet PDF (`ROADMAP.md` D11/T11.2) as
/// "Label"/"Label-Nr."/"ISRC-Nr." respectively.
///
/// **`recordingLabel` is `Party?`, not `String` — changed at real-UI build
/// time (no Deliverable number; a narrow, project-owner-requested addition
/// alongside the Cues tab's own recording-info UI), reversing this field's
/// original `String?` shape.** Resolved via `PartyResolver` everywhere it's
/// displayed/exported, the same single-source-of-truth shape every other
/// right-holder reference in this app already uses (`CLAUDE.md`, "Single
/// Source of Truth") — renaming a `Label` in the directory now updates every
/// cue sheet automatically, rather than requiring the user to re-type a
/// free-text name on every cue that happens to share it. No migration
/// concern: confirmed directly (a repo-wide grep of every production code
/// path that constructs a `Cue`) that no UI ever existed to set this field
/// to a non-`nil` value before this change, so no real persisted `Project`
/// can hold one. See `docs/DECISIONS.md`.
public struct Cue: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let workNumber: String?
    public let duration: MediaDuration
    public let rightHolders: [CueRightHolder]
    public let isArrangementOfProtectedOriginal: Bool
    public let source: CueSource
    public let startTimecode: Timecode?
    public let notes: String?
    public let recordingLabel: Party?
    public let recordingLabelNumber: String?
    public let recordingISRC: String?

    public init(
        id: UUID = UUID(),
        title: String,
        workNumber: String? = nil,
        duration: MediaDuration,
        rightHolders: [CueRightHolder],
        isArrangementOfProtectedOriginal: Bool = false,
        source: CueSource,
        startTimecode: Timecode? = nil,
        notes: String? = nil,
        recordingLabel: Party? = nil,
        recordingLabelNumber: String? = nil,
        recordingISRC: String? = nil
    ) {
        self.id = id
        self.title = title
        self.workNumber = workNumber
        self.duration = duration
        self.rightHolders = rightHolders
        self.isArrangementOfProtectedOriginal = isArrangementOfProtectedOriginal
        self.source = source
        self.startTimecode = startTimecode
        self.notes = notes
        self.recordingLabel = recordingLabel
        self.recordingLabelNumber = recordingLabelNumber
        self.recordingISRC = recordingISRC
    }
}

/// Where a `Cue` came from — drives editor UI provenance display; never
/// exported to the SUISA document (SPEC.md §4.3).
///
/// **Reclassification rule** (enforced by `UpdateCueUseCase`, `ROADMAP.md`
/// D10/T10.1, not by `Cue` itself): editing any field of a `Cue` via that
/// Use Case's edit path sets `source = .manual`, regardless of the field
/// changed or the cue's prior source — see SPEC.md §4.19.
public enum CueSource: Equatable, Sendable {
    case embeddedMarker
    case detectedFromAudio
    case manual
}
