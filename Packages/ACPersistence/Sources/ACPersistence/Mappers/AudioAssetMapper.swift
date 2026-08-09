import ACCore
import Foundation

/// Converts `ACCore.AudioAsset` to/from `AudioAssetEntity`, self-contained
/// including its `embeddedMarkers`/`broadcastWaveMetadata` subtree.
enum AudioAssetMapper {
    static func toEntity(_ asset: AudioAsset) -> AudioAssetEntity {
        let entity = AudioAssetEntity(
            id: asset.id,
            originalFileName: asset.originalFileName,
            securityScopedBookmark: asset.securityScopedBookmark,
            durationSeconds: asset.duration.seconds,
            sampleRate: asset.sampleRate,
            channelCount: asset.channelCount,
            bitDepth: asset.bitDepth,
            importedAt: asset.importedAt
        )
        entity.embeddedMarkers = asset.embeddedMarkers.enumerated().map { index, marker in
            let markerEntity = EmbeddedMarkerMapper.toEntity(marker, order: index)
            markerEntity.audioAsset = entity
            return markerEntity
        }
        entity.broadcastWaveMetadata = asset.broadcastWaveMetadata.map(BroadcastWaveMetadataMapper.toEntity)
        return entity
    }

    static func toDomain(_ entity: AudioAssetEntity) -> AudioAsset {
        let embeddedMarkers = entity.embeddedMarkers
            .sorted { $0.order < $1.order }
            .map(EmbeddedMarkerMapper.toDomain)
        return AudioAsset(
            id: entity.id,
            originalFileName: entity.originalFileName,
            securityScopedBookmark: entity.securityScopedBookmark,
            duration: MediaDuration(seconds: entity.durationSeconds),
            sampleRate: entity.sampleRate,
            channelCount: entity.channelCount,
            bitDepth: entity.bitDepth,
            embeddedMarkers: embeddedMarkers,
            broadcastWaveMetadata: entity.broadcastWaveMetadata.map(BroadcastWaveMetadataMapper.toDomain),
            importedAt: entity.importedAt
        )
    }
}
