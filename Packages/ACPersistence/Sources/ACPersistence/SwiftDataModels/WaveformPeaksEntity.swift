import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.WaveformPeaks` (SPEC.md
/// §4.15).
///
/// `min`/`max` are stored as two parallel `[Float]` attributes (index `i` of
/// each corresponds to bucket `i`) rather than `resolution` individual child
/// `@Model` rows. `WaveformPeaks` exists specifically to have a bounded,
/// small (~32KB) memory footprint regardless of source file length — backing
/// that with 4096 separate relationship rows would add real per-row
/// SwiftData overhead for no benefit and works against the same bounded-size
/// invariant at the persistence layer; a `[Float]` attribute is still a
/// single flat column per entity, not per-bucket rows, so that goal holds
/// here too.
///
/// **Not** a hand-packed `Data` blob (an earlier version of this type was) —
/// that version manually reconstructed `Float` values via
/// `UnsafeRawBufferPointer.load(as:)` over byte ranges sliced from a `Data`
/// fetched back out of SwiftData, which crashed with SIGTRAP on the
/// Xcode-15.4-pinned CI runner (though not locally on a newer toolchain):
/// `load(as:)` has a strict alignment precondition that a `Data` value round
/// -tripped through SwiftData's persisted representation isn't guaranteed to
/// satisfy the way a freshly-built in-memory `Data` happens to. Native
/// `[Float]` attributes let SwiftData own that serialization instead of
/// reinventing it by hand — removing the whole class of bug, not just the
/// one instance of it. See `docs/DECISIONS.md`.
@Model
final class WaveformPeaksEntity {
    var id: UUID
    var audioAssetID: UUID
    var resolution: Int
    var minValues: [Float]
    var maxValues: [Float]

    init(id: UUID, audioAssetID: UUID, resolution: Int, minValues: [Float], maxValues: [Float]) {
        self.id = id
        self.audioAssetID = audioAssetID
        self.resolution = resolution
        self.minValues = minValues
        self.maxValues = maxValues
    }
}
