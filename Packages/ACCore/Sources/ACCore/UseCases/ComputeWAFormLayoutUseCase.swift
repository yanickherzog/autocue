import Foundation

/// Thin wrapper around `ExportRepository.computeWAFormLayout(for:)`
/// (`ROADMAP.md` D12) — the same "small wrapping Use Case" shape
/// `ComputeCueSheetLayoutUseCase` already establishes for the cue sheet's
/// own preview, applied to the WA Film form's on-screen preview.
public struct ComputeWAFormLayoutUseCase: Sendable {
    private let exportRepository: ExportRepository

    public init(exportRepository: ExportRepository) {
        self.exportRepository = exportRepository
    }

    public func compute(for project: Project) throws -> [CueSheetPageLayout] {
        try exportRepository.computeWAFormLayout(for: project)
    }
}
