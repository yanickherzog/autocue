import Foundation

/// Creates/edits `Person`/`Label` entries in one `Project`'s right-holder
/// directory (`Project.people`/`.labels`, SPEC.md §4.1) — the counterpart to
/// `DeleteRightHolderUseCase`, which only ever removes. Not named in
/// `ROADMAP.md` D7/T7.3's original file list — added because
/// `RightHolderDirectoryViewModel` needs *some* Use Case to persist a create/
/// edit through, per `CONTRIBUTING.md` §6's "ViewModels call Use Cases only";
/// see `docs/DECISIONS.md`.
///
/// **Upsert, not separate create/update methods.** `PersonEditorSheet`/
/// `LabelEditorSheet` (`ROADMAP.md` D7/T7.3) are the same sheet for both "add
/// new" and "edit existing," distinguished only by whether an id already
/// exists in the directory — a single `savePerson`/`saveLabel` per type
/// matches that one real call shape rather than forcing the caller to first
/// decide which of two methods applies.
///
/// **Replaces only the `people`/`labels` slice, via
/// `ProjectRepository.update(id:transform:)` — never a caller-side fetch
/// followed by a separate `update(_:)` call.** Same reasoning as
/// `UpdateSetupUseCase`'s doc comment, including the same confirmed
/// data-loss bug this replaced a fetch-then-`update(_:)` implementation to
/// fix: avoids clobbering a concurrent `SetupViewModel` write to the same
/// `Project`'s disjoint `setup` slice, even when both Use Cases' fetches
/// happen to land before either write does.
///
/// **Duplicate-name detection is a business rule, so it lives here, not in
/// `RightHolderDirectoryViewModel`** (`CLAUDE.md`, "Business rules... live in
/// Use Cases, not in ViewModels"). Two `Person`s with the same trimmed,
/// case-insensitive first+last name in the same `Project` are treated as a
/// duplicate — same reasoning for `Label.name` — matching a real, reported
/// bug where re-adding under a role that already had an entry created a
/// silent duplicate (see `docs/DECISIONS.md`). The check runs *inside* the
/// same atomic `update(id:transform:)` call that performs the write, against
/// the truly-current directory, not a separately-fetched snapshot — so it
/// can't itself reintroduce the fetch-then-write race this Use Case was just
/// fixed to close. Editing an existing entry (same `id`) never collides with
/// itself; it can still be flagged if it now matches a *different* entry's
/// name.
public struct UpdateRightHolderDirectoryUseCase: Sendable {
    private let projectRepository: ProjectRepository

    public init(projectRepository: ProjectRepository) {
        self.projectRepository = projectRepository
    }

    /// Replaces the existing `Person` with the same `id`, or appends `person`
    /// as a new entry if no existing entry has that `id` — unless `person`'s
    /// name duplicates a *different* existing entry's, in which case nothing
    /// is written and `.duplicateName` is returned instead.
    @discardableResult
    public func savePerson(_ person: Person, in projectID: Project.ID) async throws -> SavePersonResult {
        do {
            let updated = try await save(projectID: projectID) { project in
                if let duplicate = Self.duplicate(of: person, among: project.people) {
                    throw DuplicatePersonNameError(existing: duplicate)
                }
                return Self.upserting(person, into: project.people)
            } labels: { $0.labels }
            return .saved(updated)
        } catch let error as DuplicatePersonNameError {
            return .duplicateName(existing: error.existing)
        }
    }

    /// Replaces the existing `Label` with the same `id`, or appends `label`
    /// as a new entry if no existing entry has that `id` — unless `label`'s
    /// name duplicates a *different* existing entry's, in which case nothing
    /// is written and `.duplicateName` is returned instead.
    @discardableResult
    public func saveLabel(_ label: Label, in projectID: Project.ID) async throws -> SaveLabelResult {
        do {
            let updated = try await save(projectID: projectID) { $0.people } labels: { project in
                if let duplicate = Self.duplicate(of: label, among: project.labels) {
                    throw DuplicateLabelNameError(existing: duplicate)
                }
                return Self.upserting(label, into: project.labels)
            }
            return .saved(updated)
        } catch let error as DuplicateLabelNameError {
            return .duplicateName(existing: error.existing)
        }
    }

    private static func upserting<T: Identifiable>(_ value: T, into existing: [T]) -> [T] {
        guard let index = existing.firstIndex(where: { $0.id == value.id }) else {
            return existing + [value]
        }
        var updated = existing
        updated[index] = value
        return updated
    }

    /// `nil` if `person`'s name doesn't match any *other* entry's. Trimmed,
    /// case-insensitive first+last name match — see this type's doc comment.
    private static func duplicate(of person: Person, among existing: [Person]) -> Person? {
        existing.first { candidate in
            candidate.id != person.id &&
                candidate.firstName.normalizedForDuplicateMatch == person.firstName.normalizedForDuplicateMatch &&
                candidate.lastName.normalizedForDuplicateMatch == person.lastName.normalizedForDuplicateMatch
        }
    }

    /// `nil` if `label`'s name doesn't match any *other* entry's. Trimmed,
    /// case-insensitive name match — see this type's doc comment.
    private static func duplicate(of label: Label, among existing: [Label]) -> Label? {
        existing.first { candidate in
            candidate.id != label.id &&
                candidate.name.normalizedForDuplicateMatch == label.name.normalizedForDuplicateMatch
        }
    }

    private func save(
        projectID: Project.ID,
        people: @escaping (Project) throws -> [Person],
        labels: @escaping (Project) throws -> [Label]
    ) async throws -> Project {
        let updated = try await projectRepository.update(id: projectID) { project in
            try Project(
                id: project.id,
                name: project.name,
                createdAt: project.createdAt,
                updatedAt: Date(),
                audioAsset: project.audioAsset,
                waveformPeaks: project.waveformPeaks,
                setup: project.setup,
                cues: project.cues,
                people: people(project),
                labels: labels(project)
            )
        }
        guard let updated else {
            throw ProjectNotFoundError(projectID: projectID)
        }
        return updated
    }
}

/// The outcome of an `UpdateRightHolderDirectoryUseCase.savePerson` call.
public enum SavePersonResult: Equatable, Sendable {
    /// Save succeeded and was persisted; the caller should adopt this
    /// updated `Project` value as its new working copy.
    case saved(Project)
    /// Save was blocked because `existing` already has the same name —
    /// nothing was mutated or persisted.
    case duplicateName(existing: Person)
}

/// The outcome of an `UpdateRightHolderDirectoryUseCase.saveLabel` call.
public enum SaveLabelResult: Equatable, Sendable {
    /// Save succeeded and was persisted; the caller should adopt this
    /// updated `Project` value as its new working copy.
    case saved(Project)
    /// Save was blocked because `existing` already has the same name —
    /// nothing was mutated or persisted.
    case duplicateName(existing: Label)
}

private struct DuplicatePersonNameError: Error {
    let existing: Person
}

private struct DuplicateLabelNameError: Error {
    let existing: Label
}

private extension String {
    var normalizedForDuplicateMatch: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
