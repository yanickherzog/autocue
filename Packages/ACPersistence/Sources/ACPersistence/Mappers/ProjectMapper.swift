import ACCore
import Foundation

/// Converts `ACCore.Project` to/from `ProjectEntity`, composing every child
/// mapper. This is the only mapper that touches `ProjectEntity`'s
/// back-referencing relationships (`CueEntity.project`,
/// `PersonEntity.project`, `LabelEntity.project`) — those need the parent
/// `ProjectEntity` instance, which only this function holds.
enum ProjectMapper {
    /// Each child collection is fully materialized before being assigned to
    /// `entity.cues`/`.people`/`.labels`, with back-references set only
    /// afterward — see `CueMapper.toEntity`'s doc comment for why: writing a
    /// child's inverse-relationship property while the parent's
    /// forward-relationship assignment is still in progress is a real Swift
    /// exclusivity violation under SwiftData's macro-generated relationship
    /// accessors, confirmed via a real crash report on PR #4's CI run.
    static func toEntity(_ project: Project) -> ProjectEntity {
        let entity = ProjectEntity(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        entity.setup = SetupMapper.toEntity(project.setup)

        let cueEntities = project.cues.enumerated().map { index, cue in
            CueMapper.toEntity(cue, order: index)
        }
        entity.cues = cueEntities
        for cueEntity in cueEntities {
            cueEntity.project = entity
        }

        let personEntities = project.people.enumerated().map { index, person in
            PersonMapper.toEntity(person, order: index)
        }
        entity.people = personEntities
        for personEntity in personEntities {
            personEntity.project = entity
        }

        let labelEntities = project.labels.enumerated().map { index, label in
            LabelMapper.toEntity(label, order: index)
        }
        entity.labels = labelEntities
        for labelEntity in labelEntities {
            labelEntity.project = entity
        }

        entity.audioAsset = project.audioAsset.map(AudioAssetMapper.toEntity)
        entity.waveformPeaks = project.waveformPeaks.map(WaveformPeaksMapper.toEntity)
        return entity
    }

    static func toDomain(_ entity: ProjectEntity) throws -> Project {
        guard let setupEntity = entity.setup else {
            throw MappingError.missingRequiredChild(type: "SetupEntity", parentID: entity.id)
        }

        let cues = try entity.cues
            .sorted { $0.order < $1.order }
            .map(CueMapper.toDomain)

        return try Project(
            id: entity.id,
            name: entity.name,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            audioAsset: entity.audioAsset.map(AudioAssetMapper.toDomain),
            waveformPeaks: entity.waveformPeaks.map(WaveformPeaksMapper.toDomain),
            setup: SetupMapper.toDomain(setupEntity),
            cues: cues,
            people: entity.people.sorted { $0.order < $1.order }.map(PersonMapper.toDomain),
            labels: entity.labels.sorted { $0.order < $1.order }.map(LabelMapper.toDomain)
        )
    }
}
