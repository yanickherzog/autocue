import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.EmbeddedMarker` (SPEC.md
/// §4.10). `order` is persistence-only, same reasoning as `CueEntity.order`.
@Model
final class EmbeddedMarkerEntity {
    var id: UUID
    var order: Int
    var positionOffsetSeconds: Double
    var label: String?
    var note: String?

    var audioAsset: AudioAssetEntity?

    init(
        id: UUID,
        order: Int,
        positionOffsetSeconds: Double,
        label: String?,
        note: String?
    ) {
        self.id = id
        self.order = order
        self.positionOffsetSeconds = positionOffsetSeconds
        self.label = label
        self.note = note
        audioAsset = nil
    }
}
