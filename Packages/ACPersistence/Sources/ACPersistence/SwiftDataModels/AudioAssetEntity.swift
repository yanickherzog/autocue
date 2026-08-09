import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.AudioAsset` (SPEC.md §4.10).
@Model
final class AudioAssetEntity {
    var id: UUID
    var originalFileName: String
    var securityScopedBookmark: Data
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
        durationSeconds: Double,
        sampleRate: Double,
        channelCount: Int,
        bitDepth: Int,
        importedAt: Date
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.securityScopedBookmark = securityScopedBookmark
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.importedAt = importedAt
        embeddedMarkers = []
        broadcastWaveMetadata = nil
    }
}
