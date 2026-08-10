import Foundation

/// Writes a new `Setup` value for one `Project` (`ROADMAP.md` D7/T7.1).
///
/// **Replaces only the `setup` slice, via `ProjectRepository.update(id:transform:)`
/// — never a caller-side fetch followed by a separate `update(_:)` call.**
/// This matters because `RightHolderDirectoryViewModel` (`ROADMAP.md`
/// D7/T7.3) can be mutating `Project.people`/`.labels` in the same window,
/// concurrently, via `UpdateRightHolderDirectoryUseCase`. An earlier version
/// of this Use Case fetched the current `Project` itself and then called
/// plain `update(_:)` with a locally-built copy — that looked safe (it *did*
/// fetch fresh immediately before writing) but wasn't: two independent
/// Use Cases each doing "fetch fresh, then write" for the *same*
/// `Project.ID` can both fetch before either writes, so the second write
/// still persists a `Project` built from a pre-write snapshot and silently
/// discards the first write's change (confirmed root cause of a real
/// data-loss bug — see `docs/DECISIONS.md`). `update(id:transform:)` closes
/// that gap by making the fetch and the write one operation, serialized
/// against `UpdateRightHolderDirectoryUseCase`'s writes to the same
/// `Project.ID` — see `ProjectRepository`'s doc comment for the full
/// reasoning.
public struct UpdateSetupUseCase: Sendable {
    private let projectRepository: ProjectRepository

    public init(projectRepository: ProjectRepository) {
        self.projectRepository = projectRepository
    }

    public func update(projectID: Project.ID, setup: Setup) async throws {
        let updated = try await projectRepository.update(id: projectID) { project in
            Project(
                id: project.id,
                name: project.name,
                createdAt: project.createdAt,
                updatedAt: Date(),
                audioAsset: project.audioAsset,
                waveformPeaks: project.waveformPeaks,
                setup: setup,
                cues: project.cues,
                people: project.people,
                labels: project.labels
            )
        }
        guard updated != nil else {
            throw ProjectNotFoundError(projectID: projectID)
        }
    }
}
