import Foundation

/// `add`/`reorder` — SPEC.md §4.19 capabilities 1 and 6, kept in place but
/// **unreachable from the UI as of `ROADMAP.md` D10's second round.** The
/// project owner removed "+ Add Cue" and reorder as UI capabilities (every
/// real cue goes through detection/split, so a disconnected, position-less
/// manual cue and manual reordering were never actually needed) but asked
/// for the underlying operations to stay, unused, rather than be deleted —
/// "may be useful in a future update." Split into their own file, the same
/// way `moveBoundary` already lives in `UpdateCueUseCase+MoveBoundary.swift`,
/// both to mirror that precedent and to keep the main file under the
/// project's 400-line lint ceiling now that these two methods have no live
/// call site pulling their weight there. See `docs/DECISIONS.md` for the
/// removal record.
public extension UpdateCueUseCase {
    /// "+ Add Cue" (SPEC.md §4.19 capability 1) — a brand-new `Cue` with no
    /// tie to any position in the imported audio, using the pinned defaults
    /// (`split`'s "later half" used the same shape before D10's second round
    /// switched it to `CueAutoPopulation`): `title: ""`, `duration: .zero` (a
    /// real, always-displayable value, not a placeholder), `rightHolders: []`,
    /// `source: .manual` (never anything else — it was never a detection
    /// result to reclassify), and `startTimecode: nil` (never assigned
    /// automatically, per SPEC.md §4.3's nil-safety rule). Appended at the
    /// end of `Project.cues`; `reorder` (below) is how it's moved anywhere
    /// else. `cueID` defaults to a fresh UUID but may be supplied by the
    /// caller — same reason `split`'s `secondCueID` is — so a ViewModel can
    /// register this add's own undo (delete `cueID`) synchronously, before
    /// this async call starts.
    @discardableResult
    func add(projectID: Project.ID, cueID: Cue.ID = UUID()) async throws -> Cue {
        let updated = try await projectRepository.update(id: projectID) { project in
            let cue = Cue(
                id: cueID,
                title: "",
                duration: .zero,
                rightHolders: [],
                source: .manual
            )
            return project.replacingCues(project.cues + [cue])
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        guard let added = updated.cues.first(where: { $0.id == cueID }) else {
            throw UpdateCueUseCaseError.cueNotFound(cueID)
        }
        return added
    }

    /// Reorders `Project.cues` — display order only (SPEC.md §4.1: "order is
    /// display order, not a stored field on `Cue`"), so this is a pure array
    /// move with no field on any `Cue` changing, and — unlike every other
    /// operation in this type — no `source` reclassification. `toIndex` is a
    /// position in the array *as it stood before this cue was removed from
    /// it* (i.e. the same "index in the original array" convention
    /// `insertForUndo`'s `atIndex` already uses), clamped to
    /// `[0, cues.count - 1]` after removal so an out-of-range request lands
    /// at the nearest valid end rather than trapping. A structural mutation
    /// (SPEC.md §4.18): writes through immediately, never debounced.
    @discardableResult
    func reorder(projectID: Project.ID, cueID: Cue.ID, toIndex: Int) async throws -> [Cue] {
        let updated = try await projectRepository.update(id: projectID) { project in
            guard let fromIndex = project.cues.firstIndex(where: { $0.id == cueID }) else {
                throw UpdateCueUseCaseError.cueNotFound(cueID)
            }
            var cues = project.cues
            let cue = cues.remove(at: fromIndex)
            let clampedIndex = min(max(toIndex, 0), cues.count)
            cues.insert(cue, at: clampedIndex)
            return project.replacingCues(cues)
        }
        guard let updated else { throw ProjectNotFoundError(projectID: projectID) }
        return updated.cues
    }
}
