import Foundation

/// Structural and field-level `Cue` mutations (SPEC.md §4.3, §4.18, §4.19).
///
/// **Minimal scope for `ROADMAP.md` D9, a deliberate pull-forward from
/// D10/T10.1 — not the full type that Deliverable will eventually own.**
/// `WaveformView`'s drag-to-reposition, split, and merge gestures (D9/T9.3)
/// write through this Use Case's `moveBoundary`/`split`/`merge` methods, per
/// `SPEC.md` §4.19's already-fully-specified field-by-field rules — D9's own
/// Acceptance Criteria (a dragged boundary actually updates `startTimecode`,
/// a split/merge actually mutates `Project.cues`) are structurally
/// unverifiable without this existing, the same forward-dependency shape
/// `GenerateWaveformDetailUseCase` already set precedent for at D8/T8.5 for
/// D9/T9.3's zoom feature. `ROADMAP.md` D10/T10.1 *extends* this same file
/// with `add`/`delete`/`reorder` and the `CueTableView`/`CueRowDetailView`
/// wiring — see `docs/DECISIONS.md` for this pull-forward, flagged
/// explicitly per this project's standing rule on a Deliverable's diff
/// touching a nominally-later Deliverable's file.
///
/// Every mutation here is a structural change (SPEC.md §4.18: "structural
/// cue mutations are never debounced") — writes through to
/// `ProjectRepository` immediately, via the atomic `update(id:transform:)`
/// (never fetch-then-`update(_:)`, which would race against a concurrent
/// write from another screen — `CLAUDE.md`, "Document & Window Model").
///
/// **Undo registration is not this Use Case's job.** `UndoManager` is a
/// Presentation-layer/environment concept (`@Environment(\.undoManager)`),
/// incompatible with a stateless, singleton-injected `ACCore` Use Case per
/// `CLAUDE.md`'s "Use Cases Are Stateless." The calling ViewModel captures
/// whatever pre-mutation `Cue` state it needs from its own already-live
/// `cues` snapshot *before* calling this Use Case, and registers the inverse
/// action with the environment `UndoManager` itself.
///
/// **`Setup.totalMusicRuntime` recompute, per SPEC.md §4.14 — provisional
/// until `Settings` has a real repository (D14).** §4.14's rule gates this
/// recompute on `Settings.autoComputeTotalMusicRuntime == true`; no
/// mechanism exists yet to fetch a real, possibly-`false` `Settings` value
/// (same "no repository yet" gap `AnalysisSettings`'s own D9 call site
/// already has, per SPEC.md §4.11's own documented "Known gap"). This
/// recomputes unconditionally, matching `Settings.autoComputeTotalMusicRuntime`'s
/// documented default (`true`) — revisit once D14 adds a real `Settings`
/// repository this Use Case can actually consult.
public struct UpdateCueUseCase: Sendable {
    /// Not `private`: `UpdateCueUseCase+MoveBoundary.swift`'s extension
    /// needs this too, and `private` is file-scoped in Swift — `internal`
    /// (the default) still keeps it out of the public API.
    let projectRepository: ProjectRepository

    public init(projectRepository: ProjectRepository) {
        self.projectRepository = projectRepository
    }

    /// The general-purpose field-edit path (SPEC.md §4.19, capability 3;
    /// also D10/T10.1's direct-field-edit entry point once it exists) —
    /// `transform` may change any field(s) on `cue`; `source` is forced to
    /// `.manual` afterward regardless of what `transform` did to it or what
    /// the cue's prior `source` was, per SPEC.md §4.3's reclassification
    /// rule, so a caller can never accidentally skip it.
    @discardableResult
    public func edit(
        projectID: Project.ID,
        cueID: Cue.ID,
        transform: @escaping @Sendable (Cue) -> Cue
    ) async throws -> Cue {
        let updated = try await projectRepository.update(id: projectID) { project in
            guard let index = project.cues.firstIndex(where: { $0.id == cueID }) else {
                throw UpdateCueUseCaseError.cueNotFound(cueID)
            }
            var cues = project.cues
            cues[index] = transform(cues[index]).reclassifiedAsManual()
            return project.replacingCues(cues)
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        guard let editedCue = updated.cues.first(where: { $0.id == cueID }) else {
            throw UpdateCueUseCaseError.cueNotFound(cueID)
        }
        return editedCue
    }

    /// Splits `cueID` into two at `atOffsetSeconds` (an absolute file
    /// offset, not an offset from the cue's own start) — SPEC.md §4.19's
    /// "Split" field rules, exactly: the earlier half keeps `cue.id` and
    /// every non-position field; the later half is fresh, using "+ Add
    /// Cue"'s own defaults, spanning from the split point to the original
    /// cue's TC Out. Rejects a split within `0.001`s of either of the cue's
    /// own endpoints (the degenerate zero-length-half case) — not a "too
    /// short" rule.
    @discardableResult
    public func split(
        projectID: Project.ID,
        cueID: Cue.ID,
        atOffsetSeconds: Double
    ) async throws -> (first: Cue, second: Cue) {
        let secondCueID = UUID()
        let updated = try await projectRepository.update(id: projectID) { project in
            guard let index = project.cues.firstIndex(where: { $0.id == cueID }) else {
                throw UpdateCueUseCaseError.cueNotFound(cueID)
            }
            let original = project.cues[index]
            guard let start = original.startTimecode else {
                throw UpdateCueUseCaseError.cueHasNoStartTimecode(cueID)
            }
            let originalEnd = start.offsetSeconds + original.duration.seconds
            guard atOffsetSeconds > start.offsetSeconds + Self.splitEpsilonSeconds,
                  atOffsetSeconds < originalEnd - Self.splitEpsilonSeconds
            else {
                throw UpdateCueUseCaseError.splitOffsetTooCloseToEndpoint
            }

            let earlier = Cue(
                id: original.id,
                title: original.title,
                workNumber: original.workNumber,
                duration: MediaDuration(seconds: atOffsetSeconds - start.offsetSeconds),
                rightHolders: original.rightHolders,
                isArrangementOfProtectedOriginal: original.isArrangementOfProtectedOriginal,
                source: .manual,
                startTimecode: start,
                notes: original.notes
            )
            let later = Cue(
                id: secondCueID,
                title: "",
                duration: MediaDuration(seconds: originalEnd - atOffsetSeconds),
                rightHolders: [],
                isArrangementOfProtectedOriginal: false,
                source: .manual,
                startTimecode: Timecode(offsetSeconds: atOffsetSeconds),
                notes: nil
            )

            var cues = project.cues
            cues[index] = earlier
            cues.insert(later, at: index + 1)
            return project.replacingCues(cues)
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        guard let first = updated.cues.first(where: { $0.id == cueID }),
              let second = updated.cues.first(where: { $0.id == secondCueID })
        else {
            throw UpdateCueUseCaseError.cueNotFound(cueID)
        }
        return (first, second)
    }

    /// Merges `cueID` into its immediately preceding `Cue` in display order
    /// (`precedingCueID`) — SPEC.md §4.19's "Merge" field rules, exactly.
    /// Eligibility: `precedingCueID`'s TC Out must be within `0.001`s of
    /// `cueID`'s `startTimecode` — deliberately **not**
    /// `embeddedMarkerMergeToleranceSeconds`, a much coarser tolerance
    /// solving a different problem (SPEC.md §4.15).
    @discardableResult
    public func merge(
        projectID: Project.ID,
        precedingCueID: Cue.ID,
        cueID: Cue.ID
    ) async throws -> Cue {
        let updated = try await projectRepository.update(id: projectID) { project in
            guard let precedingIndex = project.cues.firstIndex(where: { $0.id == precedingCueID }),
                  let followingIndex = project.cues.firstIndex(where: { $0.id == cueID })
            else {
                throw UpdateCueUseCaseError.cueNotFound(cueID)
            }
            let preceding = project.cues[precedingIndex]
            let following = project.cues[followingIndex]

            guard let precedingStart = preceding.startTimecode, let followingStart = following.startTimecode else {
                throw UpdateCueUseCaseError.mergeNotContiguous
            }
            let precedingEnd = precedingStart.offsetSeconds + preceding.duration.seconds
            guard abs(precedingEnd - followingStart.offsetSeconds) <= Self.contiguityEpsilonSeconds else {
                throw UpdateCueUseCaseError.mergeNotContiguous
            }

            let result = Cue(
                id: preceding.id,
                title: preceding.title.isEmpty ? following.title : preceding.title,
                workNumber: Self.preferringEarlier(preceding.workNumber, following.workNumber),
                duration: preceding.duration + following.duration,
                rightHolders: preceding.rightHolders + following.rightHolders,
                isArrangementOfProtectedOriginal: preceding.isArrangementOfProtectedOriginal
                    || following.isArrangementOfProtectedOriginal,
                source: .manual,
                startTimecode: precedingStart,
                notes: Self.preferringEarlier(preceding.notes, following.notes)
            )

            var cues = project.cues
            cues.remove(at: followingIndex)
            // `precedingIndex` is still valid: `followingIndex` is always the
            // later position in display order (merge only ever targets the
            // *immediately preceding* cue), so removing it never shifts an
            // earlier index.
            cues[precedingIndex] = result
            return project.replacingCues(cues)
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        guard let merged = updated.cues.first(where: { $0.id == precedingCueID }) else {
            throw UpdateCueUseCaseError.cueNotFound(cueID)
        }
        return merged
    }

    /// Deletes `cueID` outright — SPEC.md §4.18's delete path (also
    /// SPEC.md §4.19 capability 2: "remove one the analysis wrongly
    /// created" is this same path, not a separate "reject detection" UI).
    /// **Minimal scope, pulled forward from D10/T10.1** the same way
    /// `moveBoundary`/`split`/`merge` already were — see this file's own
    /// top-level doc comment; `docs/DECISIONS.md` records this specific
    /// pull-forward. No confirmation, no soft-delete: the row is gone from
    /// `Project.cues` the instant this returns, exactly per §4.18's
    /// "deliberate — no confirmation dialog." Undo is the caller's
    /// responsibility, per this type's "Undo registration is not this Use
    /// Case's job" doc comment above — the ViewModel must capture the full
    /// `Cue` (and its index) from its own live snapshot *before* calling
    /// this, since once this returns there's nothing left here to recover
    /// it from.
    public func delete(projectID: Project.ID, cueID: Cue.ID) async throws {
        let updated = try await projectRepository.update(id: projectID) { project in
            guard let index = project.cues.firstIndex(where: { $0.id == cueID }) else {
                throw UpdateCueUseCaseError.cueNotFound(cueID)
            }
            var cues = project.cues
            cues.remove(at: index)
            return project.replacingCues(cues)
        }
        guard updated != nil else { throw ProjectNotFoundError(projectID: projectID) }
    }

    /// `delete`'s own undo counterpart — reinserts `cue` (its full, exact,
    /// pre-delete field values, captured by the caller before the original
    /// `delete` call) back at `atIndex`. **Not** the D10/T10.1 "+ Add Cue"
    /// entry point, which is a different operation with different defaults
    /// (a fresh, mostly-empty `Cue`) — this exists only so ⌘Z after a delete
    /// can restore the exact cue that was removed, in its original position,
    /// per SPEC.md §4.18's undo requirement. `atIndex` is clamped to the
    /// current `cues.count` so an undo racing a concurrent structural edit
    /// (e.g. another window deleted a different cue in between) still
    /// inserts somewhere valid rather than trapping.
    @discardableResult
    public func insertForUndo(projectID: Project.ID, cue: Cue, atIndex: Int) async throws -> Cue {
        let updated = try await projectRepository.update(id: projectID) { project in
            var cues = project.cues
            let clampedIndex = min(max(atIndex, 0), cues.count)
            cues.insert(cue, at: clampedIndex)
            return project.replacingCues(cues)
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        guard let reinserted = updated.cues.first(where: { $0.id == cue.id }) else {
            throw UpdateCueUseCaseError.cueNotFound(cue.id)
        }
        return reinserted
    }

    /// "Prefer the earlier value if non-empty/non-nil, otherwise the later"
    /// — SPEC.md §4.19's merge rule, stated once, shared by `workNumber` and
    /// `notes`.
    private static func preferringEarlier(_ earlier: String?, _ later: String?) -> String? {
        guard let earlier, !earlier.isEmpty else { return later }
        return earlier
    }

    private static let splitEpsilonSeconds = 0.001
    /// Shared by `merge`'s eligibility check and `moveBoundary`'s
    /// contiguous/non-contiguous branch decision (`UpdateCueUseCase
    /// +MoveBoundary.swift`) — one epsilon, not two independently-drifting
    /// copies of the same "genuinely touching" tolerance (SPEC.md §4.19).
    /// Not `private`: that file's extension needs to read it too, and
    /// `private` is file-scoped in Swift, not just type-scoped — `internal`
    /// (the default) is still invisible outside this module.
    static let contiguityEpsilonSeconds = 0.001
}

public enum UpdateCueUseCaseError: Error, Equatable {
    case cueNotFound(Cue.ID)
    case cueHasNoStartTimecode(Cue.ID)
    case splitOffsetTooCloseToEndpoint
    case mergeNotContiguous
}

/// Not `private`: `UpdateCueUseCase+MoveBoundary.swift`'s planning functions
/// need this too, and `private` is file-scoped in Swift — `internal` (the
/// default) still keeps it invisible outside this module.
extension Cue {
    func reclassifiedAsManual() -> Cue {
        Cue(
            id: id,
            title: title,
            workNumber: workNumber,
            duration: duration,
            rightHolders: rightHolders,
            isArrangementOfProtectedOriginal: isArrangementOfProtectedOriginal,
            source: .manual,
            startTimecode: startTimecode,
            notes: notes
        )
    }
}

/// Not `private`: `UpdateCueUseCase+MoveBoundary.swift` needs `replacingCues`
/// too — `internal` (the default) still keeps this out of the public
/// `Project` API, just visible module-wide instead of file-wide.
extension Project {
    /// Reconstructs `self` with `cues` replaced and `updatedAt`/
    /// `totalMusicRuntime` recomputed together — the one place `UpdateCueUseCase`
    /// needs to touch every field `Project`'s memberwise initializer
    /// requires, kept internal to this module rather than a public `Project`
    /// API, since no caller outside it needs this yet.
    func replacingCues(_ cues: [Cue]) -> Project {
        Project(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: Date(),
            audioAsset: audioAsset,
            waveformPeaks: waveformPeaks,
            setup: setup.updating(totalMusicRuntime: RecalculateTotalMusicRuntimeUseCase.recalculate(cues: cues)),
            cues: cues,
            people: people,
            labels: labels
        )
    }
}
