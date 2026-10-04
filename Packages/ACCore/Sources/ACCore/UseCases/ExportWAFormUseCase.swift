import Foundation

/// Fetches the current `Project` by id and exports the WA Film registration
/// form via `ExportRepository.exportWAForm(project:template:to:)`
/// (`ROADMAP.md` D12) — the same fetch-fresh-at-call-time shape
/// `ExportCueSheetUseCase` already establishes for the cue sheet.
///
/// **`shareValidationStrictness` gating added at T12.3** — closes the gap
/// this type's own earlier doc comment named explicitly ("gating is added
/// here once T12.3 resolves what to gate on"). Mirrors
/// `ExportCueSheetUseCase.export(projectID:format:to:shareValidationStrictness:)`
/// exactly: `ValidateWAFormUseCase.validate(_:template:)` runs against the
/// freshly-fetched `Project` before any real render/write happens, and
/// `ValidateWAFormUseCase.isExportAllowed(issues:strictness:)` decides
/// whether to proceed — the one rule a ViewModel's preemptive
/// button-enabling and this real enforcement point both share.
public struct ExportWAFormUseCase: Sendable {
    public enum Failure: Error, Equatable {
        /// Export was refused because `Settings.shareValidationStrictness ==
        /// .blockExport` and at least one `WAFormValidationIssue` remains —
        /// the same issues the WA Film tab's own validation display already
        /// reports, not a second, independently-derived list.
        case validationIssuesPresent([WAFormValidationIssue])
    }

    private let projectRepository: ProjectRepository
    private let exportRepository: ExportRepository

    public init(projectRepository: ProjectRepository, exportRepository: ExportRepository) {
        self.projectRepository = projectRepository
        self.exportRepository = exportRepository
    }

    public func export(
        projectID: Project.ID,
        template: WAFormTemplateReference,
        to destination: URL,
        shareValidationStrictness: ShareValidationStrictness
    ) -> AsyncThrowingStream<OperationProgress<URL>, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let project = try await projectRepository.fetch(id: projectID) else {
                        continuation.finish(throwing: ProjectNotFoundError(projectID: projectID))
                        return
                    }
                    let validateUseCase = ValidateWAFormUseCase(exportRepository: exportRepository)
                    let issues = try validateUseCase.validate(project, template: template)
                    guard ValidateWAFormUseCase.isExportAllowed(issues: issues, strictness: shareValidationStrictness)
                    else {
                        continuation.finish(throwing: Failure.validationIssuesPresent(issues))
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
