import ACCore
import Foundation

/// Converts `ACCore.EmbeddedMarker` to/from `EmbeddedMarkerEntity`.
enum EmbeddedMarkerMapper {
    static func toEntity(_ marker: EmbeddedMarker, order: Int) -> EmbeddedMarkerEntity {
        EmbeddedMarkerEntity(
            id: marker.id,
            order: order,
            positionOffsetSeconds: marker.position.offsetSeconds,
            label: marker.label,
            note: marker.note
        )
    }

    static func toDomain(_ entity: EmbeddedMarkerEntity) -> EmbeddedMarker {
        EmbeddedMarker(
            id: entity.id,
            position: Timecode(offsetSeconds: entity.positionOffsetSeconds),
            label: entity.label,
            note: entity.note
        )
    }
}
