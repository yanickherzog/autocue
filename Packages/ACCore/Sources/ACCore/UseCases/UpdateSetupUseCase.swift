import Foundation

/// Writes a new `Setup` value for one `Project` (`ROADMAP.md` D7/T7.1).
///
/// **Fetches the current `Project` fresh at write time, replaces only its
/// `setup` field, and persists — never trusts a caller-held, possibly-stale
/// `Project` snapshot for the parts it doesn't own.** This matters because
/// `RightHolderDirectoryViewModel` (`ROADMAP.md` D7/T7.3) can be mutating
/// `Project.people`/`.labels` in the same window, concurrently, via
/// `UpdateRightHolderDirectoryUseCase` — both Use Cases fetch-then-replace
/// their own disjoint slice rather than each holding a full `Project` copy
/// that could clobber the other's just-saved change. Same pattern
/// `DeleteRightHolderUseCase.replacing` already establishes for the
/// `people`/`labels` slice.
public struct UpdateSetupUseCase: Sendable {
    private let projectRepository: ProjectRepository

    public init(projectRepository: ProjectRepository) {
        self.projectRepository = projectRepository
    }

    public func update(projectID: Project.ID, setup: Setup) async throws {
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
            setup: setup,
            cues: project.cues,
            people: project.people,
            labels: project.labels
        )
        try await projectRepository.update(updated)
    }
}
