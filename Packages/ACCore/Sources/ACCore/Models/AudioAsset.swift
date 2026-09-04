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
    /// Whether `securityScopedBookmark` is a real security-scoped bookmark
    /// (the normal case) or a plain, non-security-scoped fallback captured
    /// because security-scoped `bookmarkData(options: .withSecurityScope, ...)`
    /// creation itself failed for this file — a real, documented macOS
    /// failure mode independent of this app's own logic, not something
    /// `ImportAudioUseCase` can avoid or retry its way out of. See "Security-
    /// scoped bookmark creation can fail entirely," SPEC.md §4.10, and
    /// `docs/DECISIONS.md`.
    ///
    /// A `.plainFallback` bookmark is genuinely usable for the remainder of
    /// the *current* app session (the sandbox extension granted at import
    /// time is still active), but — unlike `.securityScoped` — is not
    /// guaranteed to still grant access after the app relaunches. Conformances:
    /// `Equatable`, `Sendable` (`CLAUDE.md`, "Domain Model Value-Type
    /// Conformances" — no `id` field, not `Identifiable`, same shape as
    /// `TimecodeFrameRate`). `RawRepresentable` (`String`) purely so
    /// `ACPersistence` can store it as a plain column without an extra
    /// mapping enum of its own — not a SUISA/export concern.
    public enum BookmarkAccessMode: String, Equatable, Sendable {
        case securityScoped
        case plainFallback
    }

    public let id: UUID
    public let originalFileName: String
    /// Despite the field name, this holds a **plain** (non-security-scoped)
    /// bookmark whenever `bookmarkAccessMode == .plainFallback` — see that
    /// case's own doc comment. Always resolve/refresh this via
    /// `bookmarkAccessMode`, never by assuming `.withSecurityScope`
    /// unconditionally.
    public let securityScopedBookmark: Data
    public let bookmarkAccessMode: BookmarkAccessMode
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
        bookmarkAccessMode: BookmarkAccessMode = .securityScoped,
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
        self.bookmarkAccessMode = bookmarkAccessMode
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.embeddedMarkers = embeddedMarkers
        self.broadcastWaveMetadata = broadcastWaveMetadata
        self.importedAt = importedAt
    }
}
