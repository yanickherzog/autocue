import ACCore
import Foundation

/// Backs `CueDetectionProgressView` (`ROADMAP.md` D9/T9.2) — a transient
/// progress indicator for a detection run itself, not where correction
/// happens (`SPEC.md` §4.19). Calls Use Cases only, per `CONTRIBUTING.md` §6.
///
/// **Auto-triggered, not button-triggered — unlike `AudioImportViewModel`,
/// this screen has nothing to wait for.** `CueSheetSectionViewModel`
/// (D9/T9.5) only ever routes to this screen once `Project.audioAsset`/
/// `.waveformPeaks` already exist and `Project.cues` is empty, so detection
/// can start the instant the screen appears. `runDetectionIfNeeded()` is
/// guarded on `phase == .idle` — the same idempotency-guard shape
/// `SetupViewModel.load()`'s `hasLoadedInitialSetup` already establishes —
/// so a spurious SwiftUI re-render of the hosting View never re-triggers a
/// second, concurrent detection run.
///
/// **No explicit navigation away on completion.** The instant
/// `DetectCuesUseCase` persists a non-empty `Project.cues`,
/// `CueSheetSectionViewModel`'s own live `ObserveProjectsUseCase`
/// subscription re-emits and its `resumeState` flips to `.readyForReview`,
/// swapping this screen out for `CueDetectionReviewView` automatically —
/// the direct application of `CLAUDE.md`'s "Single Source of Truth"
/// live-observation pattern, not a new mechanism this ViewModel needs to
/// implement itself.
///
/// **No re-run confirmation logic here.** `CueSheetSectionViewModel` only
/// ever shows this screen when `Project.cues` is already empty, so there is
/// nothing to warn about discarding (`SPEC.md` §4.11's re-run rule) — that
/// check belongs wherever `ROADMAP.md` D10 eventually builds a "Re-run
/// Detection" affordance reachable from an already-populated Cue Sheet, not
/// here, where it would be unreachable dead code (`CONTRIBUTING.md` §2).
@Observable
@MainActor
public final class CueDetectionViewModel {
    public enum DetectionPhase: Equatable {
        case idle
        case detecting(fractionCompleted: Double)
        case completed
        case failed(message: String)
    }

    public let projectID: Project.ID
    public private(set) var phase: DetectionPhase = .idle

    private let detectCuesUseCase: DetectCuesUseCase
    private let observeProjectsUseCase: ObserveProjectsUseCase

    public init(
        projectID: Project.ID,
        detectCuesUseCase: DetectCuesUseCase,
        observeProjectsUseCase: ObserveProjectsUseCase
    ) {
        self.projectID = projectID
        self.detectCuesUseCase = detectCuesUseCase
        self.observeProjectsUseCase = observeProjectsUseCase
    }

    public func runDetectionIfNeeded() {
        guard phase == .idle else { return }
        phase = .detecting(fractionCompleted: 0)
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let project = await currentProject(), let asset = project.audioAsset else {
                    phase = .failed(message: "This project has no imported audio yet.")
                    return
                }
                // SPEC.md §4.11's "Known gap": no Settings repository exists
                // yet (D14) to source a real AnalysisSettings value from —
                // the type's own documented defaults are used directly at
                // this call site, exactly as that section already sanctions.
                for try await event in detectCuesUseCase.detectCues(
                    projectID: projectID,
                    asset: asset,
                    settings: AnalysisSettings()
                ) {
                    switch event {
                    case let .progress(update):
                        phase = .detecting(fractionCompleted: update.fractionCompleted)
                    case .completed:
                        phase = .completed
                    }
                }
            } catch {
                phase = .failed(message: error.localizedDescription)
            }
        }
    }

    /// One-shot read of the live stream's first emission — same "settles on
    /// the very first snapshot" pattern `SetupViewModel.load()` already
    /// establishes.
    private func currentProject() async -> Project? {
        for await projects in observeProjectsUseCase.observeAll() {
            return projects.first { $0.id == projectID }
        }
        return nil
    }
}
