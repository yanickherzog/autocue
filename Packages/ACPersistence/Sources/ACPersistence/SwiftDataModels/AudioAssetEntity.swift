import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.AudioAsset` (SPEC.md §4.10).
@Model
final class AudioAssetEntity {
    var id: UUID
    var originalFileName: String
    var securityScopedBookmark: Data
    /// `AudioAsset.BookmarkAccessMode.rawValue` — a plain `String` column
    /// (not a second mapping enum) since the raw value already round-trips
    /// exactly. Swift-level default (`"securityScoped"`, the pre-existing,
    /// only-ever-used mode before this field existed) lets SwiftData's
    /// lightweight migration backfill existing local rows without a
    /// migration plan — the same pattern already established for
    /// `SetupEntity`'s `exploitationTypesRawValues` addition.
    var bookmarkAccessModeRawValue: String = "securityScoped"
    var durationSeconds: Double
    var sampleRate: Double
    var channelCount: Int
    var bitDepth: Int
    var importedAt: Date

    @Relationship(deleteRule: .cascade,
                  inverse: \EmbeddedMarkerEntity.audioAsset) var embeddedMarkers: [EmbeddedMarkerEntity]
    @Relationship(deleteRule: .cascade) var broadcastWaveMetadata: BroadcastWaveMetadataEntity?

    init(
        id: UUID,
        originalFileName: String,
        securityScopedBookmark: Data,
        bookmarkAccessModeRawValue: String,
        durationSeconds: Double,
        sampleRate: Double,
        channelCount: Int,
        bitDepth: Int,
        importedAt: Date
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.securityScopedBookmark = securityScopedBookmark
        self.bookmarkAccessModeRawValue = bookmarkAccessModeRawValue
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.importedAt = importedAt
        embeddedMarkers = []
        broadcastWaveMetadata = nil
    }
}
