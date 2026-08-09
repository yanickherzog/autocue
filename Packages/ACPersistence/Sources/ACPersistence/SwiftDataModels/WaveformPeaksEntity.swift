import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.WaveformPeaks` (SPEC.md
/// §4.15).
///
/// `buckets` is stored as a single packed `Data` blob (min/max `Float` pairs,
/// 8 bytes each, in bucket order) rather than `resolution` individual child
/// `@Model` rows. `WaveformPeaks` exists specifically to have a bounded,
/// small (~32KB) memory footprint regardless of source file length — backing
/// that with 4096 separate relationship rows would add real per-row
/// SwiftData overhead for no benefit and works against the same bounded-size
/// invariant at the persistence layer. See `docs/DECISIONS.md`.
@Model
final class WaveformPeaksEntity {
    var id: UUID
    var audioAssetID: UUID
    var resolution: Int
    var bucketsData: Data

    init(id: UUID, audioAssetID: UUID, resolution: Int, bucketsData: Data) {
        self.id = id
        self.audioAssetID = audioAssetID
        self.resolution = resolution
        self.bucketsData = bucketsData
    }
}
