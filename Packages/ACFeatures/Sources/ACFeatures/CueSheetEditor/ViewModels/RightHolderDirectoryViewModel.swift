import ACCore
import Foundation

/// Backs the project-scoped `Person`/`Label` right-holder directory
/// (`ROADMAP.md` D7/T7.3) — `PersonEditorSheet`/`LabelEditorSheet`'s create/
/// edit flow and `PartyPickerView`'s listing. Calls Use Cases only, per
/// `CONTRIBUTING.md` §6.
///
/// **Does not hold a cached `Project` snapshot.** An earlier version of this
/// ViewModel held one (populated once by `loadDirectory()`, refreshed only
/// by this ViewModel's own `savePerson`/`saveLabel`/`deletePerson`/
/// `deleteLabel` mutations) so `DeleteRightHolderUseCase` would have a
/// `Project` to scan for references. That was a real, confirmed bug: a
/// `Setup` field edit that clears a `Person`/`Label` reference happens
/// through `SetupViewModel`/`UpdateSetupUseCase` — a completely different
/// ViewModel and Use Case — which never touched this ViewModel's cached
/// copy, so an immediately-following delete attempt saw a stale reference
/// and blocked a deletion that should have succeeded. `people`/`labels`
/// stay published for the directory listing/picker, but the guard-check
/// itself now happens inside `DeleteRightHolderUseCase`, atomically against
/// the truly-current persisted `Project` — see that Use Case's doc comment
/// and `docs/DECISIONS.md`.
///
/// **`Settings()` (all defaults) is passed to `DeleteRightHolderUseCase`,
/// not a real fetched value.** No `SettingsRepository` exists yet
/// (`ROADMAP.md` D14/T14.1) — `DeleteRightHolderUseCase`'s own doc comment
/// already anticipates this ("`settings` is a plain parameter, not fetched
/// ... the caller is responsible for supplying the current `Settings` value
/// ... do not add a `SettingsRepository` dependency here ahead of that
/// Deliverable"). Consequence, stated plainly rather than silently
/// swallowed: `Settings().defaultDeclarant` is always `nil` here, so the
/// delete guard's `settingsDefaultDeclarant` reference check is effectively
/// inert until D14 ships a real `Settings` value — every other reference
/// site (`Setup.producer`/`.directorOrPrincipal`/`.declarant`,
/// `Cue.rightHolders[].party`) is checked correctly regardless, since those
/// come from the real `Project`, not `Settings`.
@Observable
@MainActor
public final class RightHolderDirectoryViewModel {
    public let projectID: Project.ID
    public private(set) var people: [Person] = []
    public private(set) var labels: [Label] = []
    public var errorMessage: String?
    /// Set when a delete attempt is blocked by a still-existing reference —
    /// the View reads this to tell the user precisely what to edit first
    /// (SPEC.md §4.12), rather than a generic "can't delete" message.
    public private(set) var blockedDeleteLocations: [PartyReferenceLocation]?

    private let observeProjectsUseCase: ObserveProjectsUseCase
    private let updateRightHolderDirectoryUseCase: UpdateRightHolderDirectoryUseCase
    private let deleteRightHolderUseCase: DeleteRightHolderUseCase

    public init(
        projectID: Project.ID,
        observeProjectsUseCase: ObserveProjectsUseCase,
        updateRightHolderDirectoryUseCase: UpdateRightHolderDirectoryUseCase,
        deleteRightHolderUseCase: DeleteRightHolderUseCase
    ) {
        self.projectID = projectID
        self.observeProjectsUseCase = observeProjectsUseCase
        self.updateRightHolderDirectoryUseCase = updateRightHolderDirectoryUseCase
        self.deleteRightHolderUseCase = deleteRightHolderUseCase
    }

    /// One-shot load/refresh from the live stream's next emission. Safe to
    /// call repeatedly (e.g. every time the directory sheet is presented).
    ///
    /// **Settles (returns) on the first snapshot either way — found or
    /// not.** An earlier version `continue`d forever on a non-match, which
    /// meant a call against a deleted/stale `projectID` (`ROADMAP.md` D7)
    /// never returned at all — harmless to the render (this ViewModel's
    /// state is `@Observable`-driven, not completion-driven), but a real,
    /// silently-leaked `Task` all the same, and the same class of bug
    /// `SetupViewModel.load()`'s own identical fix addresses; see that
    /// method's doc comment. `SetupViewModel.projectNotFound` — not a
    /// second flag here — is the one source of truth
    /// `ProjectWindowView`'s defensive fallback gates on, since this
    /// ViewModel is never the sole thing loaded for a window.
    public func loadDirectory() async {
        for await projects in observeProjectsUseCase.observeAll() {
            guard let matched = projects.first(where: { $0.id == projectID }) else { break }
            people = matched.people
            labels = matched.labels
            break
        }
    }

    /// Creates a new `Person`, or replaces the existing one with the same
    /// `id` — a single sheet handles both "add new" and "edit existing"
    /// (`UpdateRightHolderDirectoryUseCase`'s own doc comment). Immediate
    /// save: a discrete, complete action, not continuous typing.
    ///
    /// Returns the Use Case's `SavePersonResult` as-is (rather than
    /// collapsing it to a `Bool`, as an earlier version of this method did)
    /// so the caller — `PersonEditorSheet`, via `PartyPickerView`/
    /// `SetupView+CollaboratorsSection` — can distinguish "saved" from
    /// "blocked because this name already exists in the directory" and keep
    /// the sheet open with an inline message instead of the earlier
    /// behavior, silently creating a duplicate `Person`.
    @discardableResult
    public func savePerson(_ person: Person) async -> SavePersonResult? {
        do {
            let result = try await updateRightHolderDirectoryUseCase.savePerson(person, in: projectID)
            if case let .saved(updated) = result {
                people = updated.people
            }
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    public func saveLabel(_ label: Label) async -> SaveLabelResult? {
        do {
            let result = try await updateRightHolderDirectoryUseCase.saveLabel(label, in: projectID)
            if case let .saved(updated) = result {
                labels = updated.labels
            }
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Clears a previously-surfaced blocked-delete message — call when the
    /// user dismisses it or starts a fresh delete attempt.
    public func clearBlockedDeleteLocations() {
        blockedDeleteLocations = nil
    }

    public func deletePerson(_ personID: Person.ID) async {
        do {
            let result = try await deleteRightHolderUseCase.deletePerson(
                personID, from: projectID, settings: Settings()
            )
            switch result {
            case let .deleted(updated):
                people = updated.people
                blockedDeleteLocations = nil
            case let .blocked(locations):
                blockedDeleteLocations = locations
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteLabel(_ labelID: Label.ID) async {
        do {
            let result = try await deleteRightHolderUseCase.deleteLabel(
                labelID, from: projectID, settings: Settings()
            )
            switch result {
            case let .deleted(updated):
                labels = updated.labels
                blockedDeleteLocations = nil
            case let .blocked(locations):
                blockedDeleteLocations = locations
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
