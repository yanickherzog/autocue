import Foundation

/// One embedded cue-point marker read from a WAV file's `cue`/`labl`/`ltxt`
/// chunks (SPEC.md §4.10).
///
/// A factual record of the source file's own contents — never edited, even to
/// correct a misjudged detection built from it; see SPEC.md §4.19 for why
/// correction happens at the `Cue` level instead.
public struct EmbeddedMarker: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let position: Timecode
    public let label: String?
    public let note: String?

    public init(
        id: UUID = UUID(),
        position: Timecode,
        label: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.position = position
        self.label = label
        self.note = note
    }
}
