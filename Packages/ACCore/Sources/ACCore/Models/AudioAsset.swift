import Foundation

/// An immutable, derived, metadata-only snapshot of an imported WAV file
/// (SPEC.md §4.10). One per `Project`, absent until an import has happened.
/// The file on disk remains the source of truth for raw audio — this type
/// never holds raw or downsampled sample data (no PCM buffer, no waveform
/// peak array), which is what keeps it safe to hold fully in memory
/// regardless of source file size, and safe to sit alongside `Foundation`-only
/// `ACCore` despite the project-wide "never load a full WAV into memory"
/// constraint. Waveform display data is `WaveformPeaks` — a separate sibling
/// field on `Project`, not nested here (SPEC.md §4.15).
///
/// `embeddedMarkers` is never edited, including to "correct" a misjudged
/// detection — see SPEC.md §4.19 for why correction happens at the `Cue`
/// level instead, leaving this type's immutability invariant intact.
public struct AudioAsset: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let originalFileName: String
    public let securityScopedBookmark: Data
    public let duration: MediaDuration
    public let sampleRate: Double
    public let channelCount: Int
    public let bitDepth: Int
    public let embeddedMarkers: [EmbeddedMarker]
    public let broadcastWaveMetadata: BroadcastWaveMetadata?
    public let importedAt: Date

    public init(
        id: UUID = UUID(),
        originalFileName: String,
        securityScopedBookmark: Data,
        duration: MediaDuration,
        sampleRate: Double,
        channelCount: Int,
        bitDepth: Int,
        embeddedMarkers: [EmbeddedMarker] = [],
        broadcastWaveMetadata: BroadcastWaveMetadata? = nil,
        importedAt: Date
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.securityScopedBookmark = securityScopedBookmark
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.embeddedMarkers = embeddedMarkers
        self.broadcastWaveMetadata = broadcastWaveMetadata
        self.importedAt = importedAt
    }
}
