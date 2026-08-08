import Foundation

/// One SUISA "musical work" entry — many per `Project`. Display order lives on
/// `Project.cues` (an ordered `[Cue]`), not stored as a field here (SPEC.md
/// §4.1, §4.3).
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

    public init(
        id: UUID = UUID(),
        title: String,
        workNumber: String? = nil,
        duration: MediaDuration,
        rightHolders: [CueRightHolder],
        isArrangementOfProtectedOriginal: Bool = false,
        source: CueSource,
        startTimecode: Timecode? = nil,
        notes: String? = nil
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
