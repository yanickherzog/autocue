import Foundation

/// Fetches the current `Project` by id and exports it via `ExportRepository`
/// (`ROADMAP.md` D11/T11.5), enforcing SPEC.md §4.6's blocking rule: a
/// `Project` with outstanding validation issues is refused when
/// `Settings.shareValidationStrictness == .blockExport`, allowed through when
/// `.warnOnly` — the issues are already visible in the same combined Review &
/// Export screen (`CLAUDE.md`'s Navigation Model), so "warn" doesn't need a
/// second confirmation step here, only "block" needs real enforcement.
///
/// **`ValidateCueSheetUseCase` deliberately never applies this strictness
/// rule itself** — its own doc comment names this Use Case as the one place
/// that does, per SPEC.md §4.6 ("that's a policy decision about what to *do*
/// with a reported issue, not part of detecting one").
///
/// A stateless struct holding only `Sendable` protocol references, per
/// `CLAUDE.md`'s "Use Cases Are Stateless."
public struct ExportCueSheetUseCase: Sendable {
    public enum Failure: Error, Equatable {
        /// Export was refused because `Settings.shareValidationStrictness ==
        /// .blockExport` and at least one issue remains — the same issues
        /// `ValidateCueSheetUseCase`/`ReviewViewModel` already report, not a
        /// second, independently-derived list.
        case validationIssuesPresent([CueSheetValidationIssue])
    }

    private let projectRepository: ProjectRepository
    private let exportRepository: ExportRepository

    public init(projectRepository: ProjectRepository, exportRepository: ExportRepository) {
        self.projectRepository = projectRepository
        self.exportRepository = exportRepository
    }

    /// Whether a `Project` reporting `issues` may be exported under
    /// `strictness` — pure and stateless, so it's the single source of truth
    /// both `export(projectID:...)`'s own enforcement below and a
    /// ViewModel's preemptive button-enabling can share, rather than the
    /// same boolean rule being defined in two places (`CLAUDE.md` rule 7).
    public static func isExportAllowed(
        issues: [CueSheetValidationIssue],
        strictness: ShareValidationStrictness
    ) -> Bool {
        issues.isEmpty || strictness == .warnOnly
    }

    /// Fetches `projectID`'s current data fresh at call time — deliberately
    /// not a value the caller already has cached from a live subscription
    /// elsewhere (e.g. `ReviewViewModel.setup`/`.cues`), since reconstructing
    /// a full `Project` from a screen's own partial, display-oriented fields
    /// risks silently dropping data that screen never needed to hold (e.g.
    /// `audioAsset`/`waveformPeaks`).
    public func export(
        projectID: Project.ID,
        format: ExportFormat,
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
                    let issues = ValidateCueSheetUseCase.validate(project)
                    guard Self.isExportAllowed(issues: issues, strictness: shareValidationStrictness) else {
                        continuation.finish(throwing: Failure.validationIssuesPresent(issues))
                        return
                    }
                    for try await progress in exportRepository.export(
                        project: project,
                        format: format,
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
