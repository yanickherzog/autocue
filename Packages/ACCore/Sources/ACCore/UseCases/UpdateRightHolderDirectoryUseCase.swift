import Foundation

/// Creates/edits `Person`/`Label` entries in one `Project`'s right-holder
/// directory (`Project.people`/`.labels`, SPEC.md §4.1) — the counterpart to
/// `DeleteRightHolderUseCase`, which only ever removes. Not named in
/// `ROADMAP.md` D7/T7.3's original file list — added because
/// `RightHolderDirectoryViewModel` needs *some* Use Case to persist a create/
/// edit through, per `CONTRIBUTING.md` §6's "ViewModels call Use Cases only";
/// see `docs/DECISIONS.md`.
///
/// **Upsert, not separate create/update methods.** `PersonEditorSheet`/
/// `LabelEditorSheet` (`ROADMAP.md` D7/T7.3) are the same sheet for both "add
/// new" and "edit existing," distinguished only by whether an id already
/// exists in the directory — a single `savePerson`/`saveLabel` per type
/// matches that one real call shape rather than forcing the caller to first
/// decide which of two methods applies.
///
/// **Fetches the current `Project` fresh at write time, replaces only the
/// `people`/`labels` slice, and persists** — same reasoning as
/// `UpdateSetupUseCase`'s doc comment: avoids clobbering a concurrent
/// `SetupViewModel` write to the same `Project`'s disjoint `setup` slice.
public struct UpdateRightHolderDirectoryUseCase: Sendable {
    private let projectRepository: ProjectRepository

    public init(projectRepository: ProjectRepository) {
        self.projectRepository = projectRepository
    }

    /// Replaces the existing `Person` with the same `id`, or appends `person`
    /// as a new entry if no existing entry has that `id`.
    @discardableResult
    public func savePerson(_ person: Person, in projectID: Project.ID) async throws -> Project {
        try await save(projectID: projectID) { project in
            Self.upserting(person, into: project.people)
        } labels: { $0.labels }
    }

    /// Replaces the existing `Label` with the same `id`, or appends `label`
    /// as a new entry if no existing entry has that `id`.
    @discardableResult
    public func saveLabel(_ label: Label, in projectID: Project.ID) async throws -> Project {
        try await save(projectID: projectID) { $0.people } labels: { project in
            Self.upserting(label, into: project.labels)
        }
    }

    private static func upserting<T: Identifiable>(_ value: T, into existing: [T]) -> [T] {
        guard let index = existing.firstIndex(where: { $0.id == value.id }) else {
            return existing + [value]
        }
        var updated = existing
        updated[index] = value
        return updated
    }

    private func save(
        projectID: Project.ID,
        people: (Project) -> [Person],
        labels: (Project) -> [Label]
    ) async throws -> Project {
        guard let project = try await projectRepository.fetch(id: projectID) else {
            throw ProjectNotFoundError(projectID: projectID)
        }
        let updated = Project(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: Date(),
            audioAsset: project.audioAsset,
            waveformPeaks: project.waveformPeaks,
            setup: project.setup,
            cues: project.cues,
            people: people(project),
            labels: labels(project)
        )
        try await projectRepository.update(updated)
        return updated
    }
}
