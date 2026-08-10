import Foundation

/// Deletes a `Project` outright (`ROADMAP.md` D6/T6.2) — distinct from
/// `DeleteRightHolderUseCase`, which removes a `Person`/`Label` *from* a
/// `Project`'s directory, not the `Project` itself. No delete-guard applies
/// here: unlike a `Person`/`Label`, nothing else in the domain model
/// references a `Project` by id, so there's no dangling-reference risk to
/// check for before removing one.
public struct DeleteProjectUseCase: Sendable {
    private let projectRepository: ProjectRepository

    public init(projectRepository: ProjectRepository) {
        self.projectRepository = projectRepository
    }

    public func delete(id: Project.ID) async throws {
        try await projectRepository.delete(id: id)
    }
}
