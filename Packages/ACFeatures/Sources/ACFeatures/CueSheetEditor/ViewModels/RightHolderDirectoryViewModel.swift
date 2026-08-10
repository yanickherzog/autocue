import ACCore
import Foundation

/// Backs the project-scoped `Person`/`Label` right-holder directory
/// (`ROADMAP.md` D7/T7.3) — `PersonEditorSheet`/`LabelEditorSheet`'s create/
/// edit flow and `PartyPickerView`'s listing. Calls Use Cases only, per
/// `CONTRIBUTING.md` §6.
///
/// Holds a full `Project` snapshot (not just `people`/`labels`), because
/// `DeleteRightHolderUseCase.deletePerson`/`.deleteLabel` need the whole
/// `Project` to scan for references (SPEC.md §4.12) — this ViewModel doesn't
/// reimplement that scan, it supplies the data the existing Use Case's
/// pre-built guard already checks.
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

    private var project: Project?

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
    public func loadDirectory() async {
        for await projects in observeProjectsUseCase.observeAll() {
            guard let matched = projects.first(where: { $0.id == projectID }) else { continue }
            project = matched
            people = matched.people
            labels = matched.labels
            break
        }
    }

    /// Creates a new `Person`, or replaces the existing one with the same
    /// `id` — a single sheet handles both "add new" and "edit existing"
    /// (`UpdateRightHolderDirectoryUseCase`'s own doc comment). Immediate
    /// save: a discrete, complete action, not continuous typing.
    @discardableResult
    public func savePerson(_ person: Person) async -> Bool {
        do {
            let updated = try await updateRightHolderDirectoryUseCase.savePerson(person, in: projectID)
            project = updated
            people = updated.people
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func saveLabel(_ label: Label) async -> Bool {
        do {
            let updated = try await updateRightHolderDirectoryUseCase.saveLabel(label, in: projectID)
            project = updated
            labels = updated.labels
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Clears a previously-surfaced blocked-delete message — call when the
    /// user dismisses it or starts a fresh delete attempt.
    public func clearBlockedDeleteLocations() {
        blockedDeleteLocations = nil
    }

    public func deletePerson(_ personID: Person.ID) async {
        guard let project else { return }
        do {
            let result = try await deleteRightHolderUseCase.deletePerson(
                personID, from: project, settings: Settings()
            )
            switch result {
            case let .deleted(updated):
                self.project = updated
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
        guard let project else { return }
        do {
            let result = try await deleteRightHolderUseCase.deleteLabel(labelID, from: project, settings: Settings())
            switch result {
            case let .deleted(updated):
                self.project = updated
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
