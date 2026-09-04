import ACCore
import Foundation

/// Which screen the Cue Sheet section's `.cueSheet` tab should show right
/// now, derived purely from `Project.audioAsset`/`.waveformPeaks`/`.cues`
/// (SPEC.md §4.21) — a state machine over three already-existing sibling
/// fields, not new data. `AudioAsset`/`WaveformPeaks` are carried as
/// associated values so the routed-to screen doesn't have to independently
/// re-derive them.
public enum CueSheetResumeState: Equatable {
    /// Before the first `ObserveProjectsUseCase.observeAll()` emission
    /// arrives.
    case loading
    case needsImport
    case needsWaveformGeneration(AudioAsset)
    case needsCueDetection(AudioAsset, WaveformPeaks)
    case readyForReview(AudioAsset, WaveformPeaks)
}

/// Decides which of `AudioImportView`/`CueDetectionProgressView`/
/// `CueDetectionReviewView` `ProjectWindowView`'s `.cueSheet` tab shows —
/// the routing coordinator SPEC.md §4.21/`ROADMAP.md` D9/T9.5 specifies,
/// closing the real gap where reopening an already-processed Project (or
/// one interrupted mid-pipeline) would otherwise always re-show the D8
/// import prompt.
///
/// **Architectural home, not `AudioImportViewModel` and not `AppState`** —
/// see `SPEC.md` §4.21 for the full reasoning: this decision needs an async
/// read of `Project` state before any of the three candidate screens' own
/// ViewModels is even the right one to construct, which doesn't fit inside
/// `AudioImportViewModel` without inverting its purpose, and is
/// architecturally foreclosed from `AppState`, which holds no business data
/// (`CLAUDE.md`, "Document & Window Model").
///
/// Constructed once per window, the same `@State`-held,
/// `DependencyContainer`-factory pattern `SetupViewModel`/
/// `AudioImportViewModel` already establish — self-loads asynchronously
/// against `ObserveProjectsUseCase.observeAll()`, so `resumeState` stays
/// live across the window's lifetime (a fresh detection run or a structural
/// cue edit elsewhere naturally re-routes this tab with no explicit
/// navigation call).
@Observable
@MainActor
public final class CueSheetSectionViewModel {
    public let projectID: Project.ID
    public private(set) var resumeState: CueSheetResumeState = .loading

    private let observeProjectsUseCase: ObserveProjectsUseCase

    public init(projectID: Project.ID, observeProjectsUseCase: ObserveProjectsUseCase) {
        self.projectID = projectID
        self.observeProjectsUseCase = observeProjectsUseCase
    }

    public func load() async {
        for await projects in observeProjectsUseCase.observeAll() {
            guard let project = projects.first(where: { $0.id == projectID }) else { continue }
            resumeState = Self.resumeState(for: project)
        }
    }

    private static func resumeState(for project: Project) -> CueSheetResumeState {
        guard let audioAsset = project.audioAsset else { return .needsImport }
        guard let waveformPeaks = project.waveformPeaks else { return .needsWaveformGeneration(audioAsset) }
        guard !project.cues.isEmpty else { return .needsCueDetection(audioAsset, waveformPeaks) }
        return .readyForReview(audioAsset, waveformPeaks)
    }
}
