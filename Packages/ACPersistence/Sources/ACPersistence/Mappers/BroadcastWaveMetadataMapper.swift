import ACCore
import Foundation

/// Converts `ACCore.BroadcastWaveMetadata` to/from `BroadcastWaveMetadataEntity`.
enum BroadcastWaveMetadataMapper {
    static func toEntity(_ metadata: BroadcastWaveMetadata) -> BroadcastWaveMetadataEntity {
        BroadcastWaveMetadataEntity(
            descriptionText: metadata.description,
            originator: metadata.originator,
            originatorReference: metadata.originatorReference,
            originationDate: metadata.originationDate,
            timeReferenceSamples: metadata.timeReferenceSamples
        )
    }

    static func toDomain(_ entity: BroadcastWaveMetadataEntity) -> BroadcastWaveMetadata {
        BroadcastWaveMetadata(
            description: entity.descriptionText,
            originator: entity.originator,
            originatorReference: entity.originatorReference,
            originationDate: entity.originationDate,
            timeReferenceSamples: entity.timeReferenceSamples
        )
    }
}
