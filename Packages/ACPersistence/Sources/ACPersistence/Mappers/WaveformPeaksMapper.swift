import ACCore
import Foundation

/// Converts `ACCore.WaveformPeaks` to/from `WaveformPeaksEntity`. `buckets`
/// is packed into a single `Data` blob (min/max `Float` pairs, in order) —
/// see `WaveformPeaksEntity`'s doc comment for why this is stored as one
/// blob rather than `resolution` child rows.
enum WaveformPeaksMapper {
    static func toEntity(_ peaks: WaveformPeaks) -> WaveformPeaksEntity {
        WaveformPeaksEntity(
            id: peaks.id,
            audioAssetID: peaks.audioAssetID,
            resolution: peaks.resolution,
            bucketsData: pack(peaks.buckets)
        )
    }

    static func toDomain(_ entity: WaveformPeaksEntity) throws -> WaveformPeaks {
        try WaveformPeaks(
            id: entity.id,
            audioAssetID: entity.audioAssetID,
            resolution: entity.resolution,
            buckets: unpack(entity.bucketsData, expectedCount: entity.resolution)
        )
    }

    private static func pack(_ buckets: [WaveformPeakBucket]) -> Data {
        var data = Data(capacity: buckets.count * MemoryLayout<Float>.size * 2)
        for bucket in buckets {
            withUnsafeBytes(of: bucket.min) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: bucket.max) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func unpack(_ data: Data, expectedCount: Int) throws -> [WaveformPeakBucket] {
        let bucketByteCount = MemoryLayout<Float>.size * 2
        guard data.count == expectedCount * bucketByteCount else {
            throw MappingError.corruptWaveformPeaksData(
                expectedByteCount: expectedCount * bucketByteCount,
                actualByteCount: data.count
            )
        }

        var buckets: [WaveformPeakBucket] = []
        buckets.reserveCapacity(expectedCount)
        var offset = data.startIndex
        for _ in 0 ..< expectedCount {
            let min = data[offset ..< offset + 4].withUnsafeBytes { $0.load(as: Float.self) }
            offset += 4
            let max = data[offset ..< offset + 4].withUnsafeBytes { $0.load(as: Float.self) }
            offset += 4
            buckets.append(WaveformPeakBucket(min: min, max: max))
        }
        return buckets
    }
}
