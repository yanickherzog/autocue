import Foundation

/// Thrown by a Use Case that fetches a `Project` by id before mutating a
/// slice of it (`UpdateSetupUseCase`, `UpdateRightHolderDirectoryUseCase`)
/// when no `Project` with that id exists — e.g. it was deleted from the
/// Library window while a Project window still had it open, a real gap
/// `OpenProjectWindowRegistry` (`CLAUDE.md`, "Document & Window Model") does
/// not currently guard against. Handled explicitly, not force-unwrapped.
public struct ProjectNotFoundError: Error, Equatable, Sendable {
    public let projectID: Project.ID

    public init(projectID: Project.ID) {
        self.projectID = projectID
    }
}
