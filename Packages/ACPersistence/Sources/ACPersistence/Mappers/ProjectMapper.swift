import ACCore
import Foundation

/// Converts `ACCore.Project` to/from `ProjectEntity`, composing every child
/// mapper. This is the only mapper that touches `ProjectEntity`'s
/// back-referencing relationships (`CueEntity.project`,
/// `PersonEntity.project`, `LabelEntity.project`) — those need the parent
/// `ProjectEntity` instance, which only this function holds.
enum ProjectMapper {
    static func toEntity(_ project: Project) -> ProjectEntity {
        let entity = ProjectEntity(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        entity.setup = SetupMapper.toEntity(project.setup)
        entity.cues = project.cues.enumerated().map { index, cue in
            let cueEntity = CueMapper.toEntity(cue, order: index)
            cueEntity.project = entity
            return cueEntity
        }
        entity.people = project.people.enumerated().map { index, person in
            let personEntity = PersonMapper.toEntity(person, order: index)
            personEntity.project = entity
            return personEntity
        }
        entity.labels = project.labels.enumerated().map { index, label in
            let labelEntity = LabelMapper.toEntity(label, order: index)
            labelEntity.project = entity
            return labelEntity
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
