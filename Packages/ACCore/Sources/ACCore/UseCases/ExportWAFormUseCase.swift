import Foundation

/// Fetches the current `Project` by id and exports the WA Film registration
/// form via `ExportRepository.exportWAForm(project:template:to:)`
/// (`ROADMAP.md` D12) — the same fetch-fresh-at-call-time shape
/// `ExportCueSheetUseCase` already establishes for the cue sheet.
///
/// **No `shareValidationStrictness` gating yet, unlike `ExportCueSheetUseCase`
/// — deliberate, not an oversight.** This form's own export-readiness rules
/// (e.g. the right-holder-row and continuation-page capacity ceilings a real
/// paper form imposes that the cue sheet never had) are `ROADMAP.md` T12.3's
/// job, not yet decided at the point this Task was built — see
/// `docs/DECISIONS.md`. Gating is added here once T12.3 resolves what to
/// gate on, the same incremental sequencing D11 already used (T11.1's
/// `ValidateCueSheetUseCase` existed before T11.5 wired its gate).
public struct ExportWAFormUseCase: Sendable {
    private let projectRepository: ProjectRepository
    private let exportRepository: ExportRepository

    public init(projectRepository: ProjectRepository, exportRepository: ExportRepository) {
        self.projectRepository = projectRepository
        self.exportRepository = exportRepository
    }

    public func export(
        projectID: Project.ID,
        template: WAFormTemplateReference,
        to destination: URL
    ) -> AsyncThrowingStream<OperationProgress<URL>, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let project = try await projectRepository.fetch(id: projectID) else {
                        continuation.finish(throwing: ProjectNotFoundError(projectID: projectID))
                        return
                    }
                    for try await progress in exportRepository.exportWAForm(
                        project: project,
                        template: template,
                        to: destination
                    ) {
                        continuation.yield(progress)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
