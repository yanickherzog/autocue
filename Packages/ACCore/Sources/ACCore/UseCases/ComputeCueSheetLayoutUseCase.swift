import Foundation

/// Thin wrapper around `ExportRepository.computeLayout(for:)` (SPEC.md
/// §4.16) — the "small wrapping Use Case" `CLAUDE.md`'s Dependency
/// Injection Pattern requires so the on-screen preview ViewModel (`ACFeatures`
/// `ROADMAP.md` D11/T11.2) calls a Use Case rather than holding an
/// `ExportRepository` reference directly, consistent with `CONTRIBUTING.md`
/// §6's "ViewModels call Use Cases only" — the same shape
/// `ObserveProjectsUseCase` already establishes for `ProjectRepository
/// .observeAll()`.
public struct ComputeCueSheetLayoutUseCase: Sendable {
    private let exportRepository: ExportRepository

    public init(exportRepository: ExportRepository) {
        self.exportRepository = exportRepository
    }

    public func compute(for project: Project) -> [CueSheetPageLayout] {
        exportRepository.computeLayout(for: project)
    }
}
