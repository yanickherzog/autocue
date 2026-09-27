import ACCore
import Foundation

/// Backs `ReviewView` (`ROADMAP.md` D11/T11.1) — the validation-summary half
/// of the combined Review & Export destination (composed into the actual
/// navigable screen at T11.5, per `CLAUDE.md`'s Navigation Model).
///
/// **One live subscription is the single source of truth for `issues`** —
/// never a separately-mutated cache, and never an explicit "refresh" method.
/// A structural edit made anywhere else in the app (e.g.
/// `CueDetectionReviewViewModel` deleting a `Cue`) writes through
/// `ProjectRepository` immediately (SPEC.md §4.18) and republishes into the
/// same `observeAll()` stream this ViewModel is already subscribed to — the
/// concrete cross-ViewModel propagation `ROADMAP.md` D11's own Acceptance
/// Criteria requires proving, not just asserting by architecture.
@Observable
@MainActor
public final class ReviewViewModel {
    public let projectID: Project.ID
    public private(set) var issues: [CueSheetValidationIssue] = []
    public private(set) var setup: Setup?
    public private(set) var cues: [Cue] = []
    public private(set) var people: [Person] = []
    public private(set) var labels: [Label] = []
    /// Owned by `Setup.totalMusicRuntime` (SPEC.md §4.14); displayed here per
    /// the original product brief's "shown once the cue sheet is actually
    /// filled out" placement — deliberately not shown on the Setup screen
    /// (`SetupView+ProductionSection.swift`'s own doc comment).
    public var totalMusicRuntime: MediaDuration {
        setup?.totalMusicRuntime ?? .zero
    }

    public private(set) var projectNotFound = false

    private let observeProjectsUseCase: ObserveProjectsUseCase

    public init(projectID: Project.ID, observeProjectsUseCase: ObserveProjectsUseCase) {
        self.projectID = projectID
        self.observeProjectsUseCase = observeProjectsUseCase
    }

    /// Runs for the whole screen's lifetime (called once from the hosting
    /// View's `.task`), the same shape `CueDetectionReviewViewModel.load()`
    /// already establishes — every subsequent mutation to this `Project`,
    /// from any screen, republishes here live. Settles `projectNotFound`
    /// immediately and stops if this `Project` genuinely doesn't exist
    /// (`SetupViewModel.load()`'s own precedent for why looping forever on a
    /// non-match would be wrong) — but, unlike `SetupViewModel`, keeps
    /// consuming the stream indefinitely once found, since this screen has
    /// no working copy of its own to protect from live overwrites.
    public func load() async {
        for await projects in observeProjectsUseCase.observeAll() {
            guard let project = projects.first(where: { $0.id == projectID }) else {
                projectNotFound = true
                break
            }
            projectNotFound = false
            setup = project.setup
            cues = project.cues
            people = project.people
            labels = project.labels
            issues = ValidateCueSheetUseCase.validate(project)
        }
    }
}
