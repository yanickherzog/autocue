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
/// `Project.ID` it's editing. Do not add a `SettingsRepository` dependency
/// here ahead of that Deliverable.
///
/// **Takes `projectID: Project.ID`, not a caller-supplied `Project` snapshot
/// — the guard-check and the write both run against the truly-current
/// persisted `Project`, fetched and written atomically via
/// `ProjectRepository.update(id:transform:)`.** An earlier version of this
/// Use Case took `from project: Project` directly, trusting whatever
/// snapshot the caller happened to be holding. That caused a real, confirmed
/// bug: `RightHolderDirectoryViewModel` cached its own `Project` snapshot,
/// refreshed only by its *own* mutations — clearing `Setup.declarant` via
/// `SetupViewModel`/`UpdateSetupUseCase` (a different ViewModel, writing
/// through a different Use Case) never told `RightHolderDirectoryViewModel`
/// its cached snapshot was now stale, so a delete attempt immediately after
/// clearing the only reference still saw the old, now-incorrect reference
/// and blocked a deletion that should have succeeded. Fetching fresh inside
/// the same atomic operation as the write — the same `update(id:transform:)`
/// mechanism `UpdateSetupUseCase`/`UpdateRightHolderDirectoryUseCase` already
/// use — closes this permanently: the guard-check always runs against
/// whatever the most recent completed write for this `Project.ID` actually
/// persisted, never a ViewModel-held copy of it. See `docs/DECISIONS.md`.
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

        if project.setup.producer.contains(party) {
            locations.append(.setupProducer)
        }
        if project.setup.directorOrPrincipal.contains(party) {
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

    /// Deletes `personID` from the `Project` identified by `projectID`, or
    /// returns every blocking reference if `.person(personID)` is still
    /// referenced anywhere in the *truly-current* persisted `Project`.
    public func deletePerson(
        _ personID: Person.ID,
        from projectID: Project.ID,
        settings: Settings
    ) async throws -> DeletePartyResult {
        try await delete(.person(personID), from: projectID, settings: settings) { project in
            Self.replacing(project, people: project.people.filter { $0.id != personID })
        }
    }

    /// Deletes `labelID` from the `Project` identified by `projectID`, or
    /// returns every blocking reference if `.label(labelID)` is still
    /// referenced anywhere in the *truly-current* persisted `Project`.
    public func deleteLabel(
        _ labelID: Label.ID,
        from projectID: Project.ID,
        settings: Settings
    ) async throws -> DeletePartyResult {
        try await delete(.label(labelID), from: projectID, settings: settings) { project in
            Self.replacing(project, labels: project.labels.filter { $0.id != labelID })
        }
    }

    /// `Project`'s fields are all `let` — there's no in-place mutation, even
    /// on a `var` copy, so removal goes through reconstruction via the
    /// memberwise initializer instead. Bumps `updatedAt` to now: a
    /// successful `Person`/`Label` removal is a real mutation to the
    /// `Project`'s data (SPEC.md §4.1), the same as any other write through
    /// `ProjectRepository` — `updatedAt` isn't scoped to a narrower subset
    /// of fields anywhere in SPEC.md/CLAUDE.md.
    private static func replacing(
        _ project: Project,
        people: [Person]? = nil,
        labels: [Label]? = nil
    ) -> Project {
        Project(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: Date(),
            audioAsset: project.audioAsset,
            waveformPeaks: project.waveformPeaks,
            setup: project.setup,
            cues: project.cues,
            people: people ?? project.people,
            labels: labels ?? project.labels
        )
    }

    /// The guard-check and the write happen inside the same `transform`
    /// closure — i.e. the same atomic, per-`Project.ID`-serialized operation
    /// — so there is no window between "read the current `Project` to check
    /// references" and "persist the removal" where a concurrent write for
    /// this same `Project.ID` (e.g. a Setup field being cleared) could land
    /// unseen. A blocked delete throws a private sentinel error to abort the
    /// write entirely — nothing is persisted, `updatedAt` doesn't move —
    /// caught immediately below and converted back to `.blocked`.
    private func delete(
        _ party: Party,
        from projectID: Project.ID,
        settings: Settings,
        removing: @escaping @Sendable (Project) -> Project
    ) async throws -> DeletePartyResult {
        do {
            let updated = try await projectRepository.update(id: projectID) { project in
                let locations = Self.referenceLocations(for: party, in: project, settings: settings)
                guard locations.isEmpty else {
                    throw BlockedDeleteError(locations: locations)
                }
                return removing(project)
            }
            guard let updated else {
                throw ProjectNotFoundError(projectID: projectID)
            }
            return .deleted(updated)
        } catch let error as BlockedDeleteError {
            return .blocked(error.locations)
        }
    }
}

private struct BlockedDeleteError: Error {
    let locations: [PartyReferenceLocation]
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
