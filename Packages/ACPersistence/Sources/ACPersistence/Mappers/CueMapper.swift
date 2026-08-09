import ACCore
import Foundation

/// Converts `ACCore.Cue` to/from `CueEntity`, self-contained including its
/// `rightHolders` subtree (`CueRightHolderEntity.cue` back-references are set
/// here, since this function is the one holding the newly-created `CueEntity`
/// instance to reference — the same self-contained-subtree pattern
/// `AudioAssetMapper` uses for `embeddedMarkers`).
enum CueMapper {
    static func toEntity(_ cue: Cue, order: Int) -> CueEntity {
        let entity = CueEntity(
            id: cue.id,
            order: order,
            title: cue.title,
            workNumber: cue.workNumber,
            durationSeconds: cue.duration.seconds,
            isArrangementOfProtectedOriginal: cue.isArrangementOfProtectedOriginal,
            source: rawValue(for: cue.source),
            startTimecodeOffsetSeconds: cue.startTimecode?.offsetSeconds,
            notes: cue.notes
        )
        entity.rightHolders = cue.rightHolders.enumerated().map { index, rightHolder in
            let rightHolderEntity = CueRightHolderMapper.toEntity(rightHolder, order: index)
            rightHolderEntity.cue = entity
            return rightHolderEntity
        }
        return entity
    }

    static func toDomain(_ entity: CueEntity) throws -> Cue {
        let rightHolders = try entity.rightHolders
            .sorted { $0.order < $1.order }
            .map(CueRightHolderMapper.toDomain)
        return try Cue(
            id: entity.id,
            title: entity.title,
            workNumber: entity.workNumber,
            duration: MediaDuration(seconds: entity.durationSeconds),
            rightHolders: rightHolders,
            isArrangementOfProtectedOriginal: entity.isArrangementOfProtectedOriginal,
            source: cueSource(from: entity.source),
            startTimecode: entity.startTimecodeOffsetSeconds.map(Timecode.init(offsetSeconds:)),
            notes: entity.notes
        )
    }

    private static func rawValue(for value: CueSource) -> String {
        switch value {
        case .embeddedMarker: "embeddedMarker"
        case .detectedFromAudio: "detectedFromAudio"
        case .manual: "manual"
        }
    }

    private static func cueSource(from rawValue: String) throws -> CueSource {
        switch rawValue {
        case "embeddedMarker": .embeddedMarker
        case "detectedFromAudio": .detectedFromAudio
        case "manual": .manual
        default: throw MappingError.unknownRawValue(type: "CueSource", rawValue: rawValue)
        }
    }
}
