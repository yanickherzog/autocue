import ACCore
import Foundation

/// Converts `ACCore.Cue` to/from `CueEntity`, self-contained including its
/// `rightHolders` subtree (`CueRightHolderEntity.cue` back-references are set
/// here, since this function is the one holding the newly-created `CueEntity`
/// instance to reference — the same self-contained-subtree pattern
/// `AudioAssetMapper` uses for `embeddedMarkers`).
enum CueMapper {
    /// Builds the child entities fully **before** assigning them to
    /// `entity.rightHolders`, and only sets each child's `cue` back-reference
    /// **after** that assignment has completed — not interleaved inside the
    /// `.map` that produces the array. This isn't stylistic: writing a child's
    /// inverse-relationship property while the parent's forward-relationship
    /// assignment is still in progress is a real Swift exclusivity violation
    /// under SwiftData's macro-generated relationship accessors (setting one
    /// side of a declared `inverse:` pair can itself touch the other side) —
    /// confirmed as the actual cause of a real `EXC_BREAKPOINT`/`SIGTRAP`
    /// crash on PR #4's CI run, via a real crash report (`swift_beginAccess`,
    /// register values naming `CueEntity`/`CueRightHolderEntity`'s type
    /// metadata), not theorized. Only reproduces with a non-empty array —
    /// `[].map { ... }` never runs the closure body — which is why it never
    /// surfaced against the minimal fixture. See `docs/DECISIONS.md`.
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
        let rightHolderEntities = cue.rightHolders.enumerated().map { index, rightHolder in
            CueRightHolderMapper.toEntity(rightHolder, order: index)
        }
        entity.rightHolders = rightHolderEntities
        for rightHolderEntity in rightHolderEntities {
            rightHolderEntity.cue = entity
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
