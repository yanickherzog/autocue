import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.Project` (SPEC.md §4.1).
///
/// Deliberately not `Sendable` (SwiftData `@Model` classes never are) — this
/// type must never cross an actor boundary or leave `ProjectRepositoryImpl`'s
/// internals. Only `ProjectMapper.toDomain`'s output (a plain `Project`
/// value) is allowed to cross that boundary. See `CLAUDE.md`, "Domain Model
/// Value-Type Conformances" — that policy governs `ACCore` value types and
/// deliberately does not apply here.
///
/// Every child relationship uses `.cascade` — SwiftData's default delete rule
/// is `.nullify`, which would silently orphan child rows on Project deletion
/// if left unspecified.
@Model
final class ProjectEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade) var setup: SetupEntity?
    @Relationship(deleteRule: .cascade, inverse: \CueEntity.project) var cues: [CueEntity]
    @Relationship(deleteRule: .cascade, inverse: \PersonEntity.project) var people: [PersonEntity]
    @Relationship(deleteRule: .cascade, inverse: \LabelEntity.project) var labels: [LabelEntity]
    @Relationship(deleteRule: .cascade) var audioAsset: AudioAssetEntity?
    @Relationship(deleteRule: .cascade) var waveformPeaks: WaveformPeaksEntity?

    init(id: UUID, name: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        setup = nil
        cues = []
        people = []
        labels = []
        audioAsset = nil
        waveformPeaks = nil
    }
}
