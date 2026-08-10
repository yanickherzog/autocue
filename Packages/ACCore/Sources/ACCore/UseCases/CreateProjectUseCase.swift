import Foundation

/// Creates a brand-new `Project` with a minimal, empty `Setup` and persists
/// it (`ROADMAP.md` D6/T6.2).
public struct CreateProjectUseCase: Sendable {
    private let projectRepository: ProjectRepository

    public init(projectRepository: ProjectRepository) {
        self.projectRepository = projectRepository
    }

    /// The default `Setup` a brand-new `Project` starts with. Pure — no
    /// Repository call, safe to unit test directly at the `ACCore` level with
    /// no mock needed, the same split `DeleteRightHolderUseCase.referenceLocations`
    /// already establishes between a Use Case's pure logic and its
    /// repository-touching orchestration.
    ///
    /// Every field here is a genuinely honest "not yet entered" value within
    /// its existing type, checked field-by-field against `SPEC.md` §4.2
    /// before this Use Case was written (`docs/DECISIONS.md`, "`Setup`'s
    /// three `Party` fields become optional") — `producer`/
    /// `directorOrPrincipal`/`declarant` are simply omitted (defaulting to
    /// `nil`, since `Party` has no honest "none" value of its own), not
    /// worked around with a fabricated placeholder reference.
    public static func makeDefaultSetup(title: String, now: Date) -> Setup {
        Setup(
            title: title,
            productionRuntime: .zero,
            totalMusicRuntime: .zero,
            // Deliberately 0, not a `Calendar`-derived current year. A
            // plausible-looking guessed year would be exactly the kind of
            // silently-satisfying default this project has already decided
            // against for Setup's other required-but-unentered fields — see
            // docs/DECISIONS.md, "Setup's three Party fields become
            // optional," for the full reasoning this default follows. Don't
            // "helpfully" change this to
            // Calendar.current.component(.year, from: now) — 0 is
            // deliberately, visibly wrong, so it reads as incomplete rather
            // than as real data.
            productionYear: 0,
            containsAdditionalUndeclaredWorks: .notKnown,
            productionTypes: [],
            declarationDate: now
        )
    }

    @discardableResult
    public func create(name: String) async throws -> Project {
        let now = Date()
        let project = Project(
            name: name,
            createdAt: now,
            updatedAt: now,
            setup: Self.makeDefaultSetup(title: name, now: now)
        )
        try await projectRepository.create(project)
        return project
    }
}
