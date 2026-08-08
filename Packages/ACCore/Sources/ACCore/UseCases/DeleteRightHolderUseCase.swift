import Foundation

/// The *only* sanctioned way to remove a `Person`/`Label` from
/// `Project.people`/`Project.labels` (SPEC.md §4.12). `Party.person`/`.label`
/// are bare `UUID` references with no SwiftData cascade/nullify behind them,
/// so deletion is blocked — never cascaded, never nulled — whenever a
/// reference to the one being deleted still exists anywhere reachable from
/// the `Project`, plus `Settings.defaultDeclarant`.
///
/// **Scope: exactly one `Project`, never across projects.** `Person`/`Label`
/// are a project-scoped right-holder directory (SPEC.md §4.1) — a `Party`
/// value in one `Project` never refers to a `Person`/`Label` living in a
/// different `Project`'s arrays. This holds even once `ROADMAP.md` D6's
/// multi-window shell exists: each open Project window edits exactly one
/// `Project` at a time (`OpenProjectWindowRegistry` prevents the same
/// `Project` from being open twice, and nothing opens more than one
/// `Project`'s data into a single delete operation). Do not "fix" this by
/// making a caller pass every open `Project` — the scan takes the one
/// `Project` the deletion applies to, by design, not as an oversight.
///
/// **`settings` is a plain parameter, not fetched.** No `SettingsRepository`
/// exists yet (`ROADMAP.md` D14/T14.1) — the caller (a future ViewModel) is
/// responsible for supplying the current `Settings` value alongside the
/// `Project` it's editing. Do not add a `SettingsRepository` dependency here
/// ahead of that Deliverable.
///
/// Both the guard-check half (pure, independently testable) and the
/// orchestration half (scans, and only if clear, removes + persists via
/// `ProjectRepository`) live together in this one type — a caller cannot
/// bypass the guard by mutating and saving a `Project` directly, since the
/// only way to actually remove a `Person`/`Label` is through this Use Case.
public struct DeleteRightHolderUseCase: Sendable {
    private let projectRepository: ProjectRepository

    public init(projectRepository: ProjectRepository) {
        self.projectRepository = projectRepository
    }

    /// Every reachable reference to `party` in `project`/`settings`, or an
    /// empty array if none exist. Pure — no Repository call, safe to unit
    /// test directly against constructed fixtures.
    public static func referenceLocations(
        for party: Party,
        in project: Project,
        settings: Settings
    ) -> [PartyReferenceLocation] {
        var locations: [PartyReferenceLocation] = []

        if project.setup.producer == party {
            locations.append(.setupProducer)
        }
        if project.setup.directorOrPrincipal == party {
            locations.append(.setupDirectorOrPrincipal)
        }
        if project.setup.declarant == party {
            locations.append(.setupDeclarant)
        }
        if settings.defaultDeclarant == party {
            locations.append(.settingsDefaultDeclarant)
        }
        for cue in project.cues where cue.rightHolders.contains(where: { $0.party == party }) {
            locations.append(.cueRightHolder(cueID: cue.id))
        }

        return locations
    }

    /// Deletes `personID` from `project.people`, or returns every blocking
    /// reference if `.person(personID)` is still referenced anywhere.
    public func deletePerson(
        _ personID: Person.ID,
        from project: Project,
        settings: Settings
    ) async throws -> DeletePartyResult {
        try await delete(.person(personID), from: project, settings: settings) { project in
            Self.replacing(project, people: project.people.filter { $0.id != personID })
        }
    }

    /// Deletes `labelID` from `project.labels`, or returns every blocking
    /// reference if `.label(labelID)` is still referenced anywhere.
    public func deleteLabel(
        _ labelID: Label.ID,
        from project: Project,
        settings: Settings
    ) async throws -> DeletePartyResult {
        try await delete(.label(labelID), from: project, settings: settings) { project in
            Self.replacing(project, labels: project.labels.filter { $0.id != labelID })
        }
    }

    /// `Project`'s fields are all `let` — there's no in-place mutation, even
    /// on a `var` copy, so removal goes through reconstruction via the
    /// memberwise initializer instead.
    private static func replacing(
        _ project: Project,
        people: [Person]? = nil,
        labels: [Label]? = nil
    ) -> Project {
        Project(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            audioAsset: project.audioAsset,
            waveformPeaks: project.waveformPeaks,
            setup: project.setup,
            cues: project.cues,
            people: people ?? project.people,
            labels: labels ?? project.labels
        )
    }

    private func delete(
        _ party: Party,
        from project: Project,
        settings: Settings,
        removing: (Project) -> Project
    ) async throws -> DeletePartyResult {
        let locations = Self.referenceLocations(for: party, in: project, settings: settings)
        guard locations.isEmpty else {
            return .blocked(locations)
        }

        let updatedProject = removing(project)
        try await projectRepository.update(updatedProject)
        return .deleted(updatedProject)
    }
}

/// Where a still-referenced `Party` was found, so the calling ViewModel/View
/// can tell the user precisely what to edit first (SPEC.md §4.12).
public enum PartyReferenceLocation: Equatable, Sendable {
    case setupProducer
    case setupDirectorOrPrincipal
    case setupDeclarant
    case settingsDefaultDeclarant
    case cueRightHolder(cueID: Cue.ID)
}

/// The outcome of a `DeleteRightHolderUseCase` deletion attempt.
public enum DeletePartyResult: Equatable, Sendable {
    /// Deletion succeeded and was persisted; the caller should adopt this
    /// updated `Project` value as its new working copy.
    case deleted(Project)
    /// Deletion was blocked — nothing was mutated or persisted.
    case blocked([PartyReferenceLocation])
}
