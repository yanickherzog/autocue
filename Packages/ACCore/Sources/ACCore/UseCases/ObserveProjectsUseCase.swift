import Foundation

/// Thin wrapper around `ProjectRepository.observeAll()` — the "small wrapping
/// Use Case" `CLAUDE.md`'s "Single Source of Truth" section already
/// anticipates for exactly this purpose, so `ProjectLibraryViewModel`
/// (`ROADMAP.md` D6/T6.2) subscribes to a Use Case rather than holding a
/// `ProjectRepository` reference directly, consistent with `CONTRIBUTING.md`
/// §6's "ViewModels call Use Cases only."
public struct ObserveProjectsUseCase: Sendable {
    private let projectRepository: ProjectRepository

    public init(projectRepository: ProjectRepository) {
        self.projectRepository = projectRepository
    }

    public func observeAll() -> AsyncStream<[Project]> {
        projectRepository.observeAll()
    }
}
