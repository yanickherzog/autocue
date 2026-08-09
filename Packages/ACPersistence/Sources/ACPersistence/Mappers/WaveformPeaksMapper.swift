import ACCore
import Foundation

/// Converts `ACCore.WaveformPeaks` to/from `WaveformPeaksEntity`. `buckets`
/// maps to/from the entity's two parallel `[Float]` attributes — see
/// `WaveformPeaksEntity`'s doc comment for why this isn't a manually
/// byte-packed `Data` blob.
enum WaveformPeaksMapper {
    static func toEntity(_ peaks: WaveformPeaks) -> WaveformPeaksEntity {
        WaveformPeaksEntity(
            id: peaks.id,
            audioAssetID: peaks.audioAssetID,
            resolution: peaks.resolution,
            minValues: peaks.buckets.map(\.min),
            maxValues: peaks.buckets.map(\.max)
        )
    }

    static func toDomain(_ entity: WaveformPeaksEntity) throws -> WaveformPeaks {
        guard entity.minValues.count == entity.resolution, entity.maxValues.count == entity.resolution else {
            throw MappingError.corruptWaveformPeaksData(
                expectedCount: entity.resolution,
                actualMinCount: entity.minValues.count,
                actualMaxCount: entity.maxValues.count
            )
        }

        let buckets = zip(entity.minValues, entity.maxValues).map(WaveformPeakBucket.init(min:max:))
        return WaveformPeaks(
            id: entity.id,
            audioAssetID: entity.audioAssetID,
            resolution: entity.resolution,
            buckets: buckets
        )
    }
}
