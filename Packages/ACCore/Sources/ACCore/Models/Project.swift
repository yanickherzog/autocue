import Foundation

/// The persisted container for one production (SPEC.md §4.1) — assembles
/// `Setup` (1:1), `[Cue]` (1:many, display order), a project-scoped
/// `[Person]`/`[Label]` right-holder directory, plus an optional
/// `AudioAsset`/`WaveformPeaks` pair. There is no separate persisted
/// `CueSheet` type — the exportable cue sheet is just `setup` + `cues`,
/// assembled on demand by `ExportCueSheetUseCase` (SPEC.md §5).
///
/// `audioAsset`/`waveformPeaks` are deliberately sibling optionals, not
/// nested inside each other — this keeps `AudioAsset`'s "metadata-only, no
/// sample data" invariant unambiguous (SPEC.md §4.1, §4.10, §4.15).
public struct Project: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let audioAsset: AudioAsset?
    public let waveformPeaks: WaveformPeaks?
    public let setup: Setup
    public let cues: [Cue]
    public let people: [Person]
    public let labels: [Label]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        updatedAt: Date,
        audioAsset: AudioAsset? = nil,
        waveformPeaks: WaveformPeaks? = nil,
        setup: Setup,
        cues: [Cue] = [],
        people: [Person] = [],
        labels: [Label] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.audioAsset = audioAsset
        self.waveformPeaks = waveformPeaks
        self.setup = setup
        self.cues = cues
        self.people = people
        self.labels = labels
    }
}
