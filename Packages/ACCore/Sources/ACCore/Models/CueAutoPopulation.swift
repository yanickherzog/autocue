import Foundation

/// Default title/right-holder generation for a freshly-created `Cue` —
/// applied at both real creation points, `DetectCuesUseCase` (detected/
/// embedded-marker cues) and `UpdateCueUseCase.split` (the later half),
/// per `ROADMAP.md` D10 and `docs/DECISIONS.md`.
///
/// A stateless, pure (no I/O, no async) namespace — the same "pure static
/// helper" shape SPEC.md §4.14 already establishes for
/// `RecalculateTotalMusicRuntimeUseCase` and §4.13 for `PartyResolver`.
public enum CueAutoPopulation {
    /// `"ProjectTitle_Score_Cue-N"` — a real, persisted default value (not a
    /// `TextField` ghost hint left over an empty `Cue.title`): this feeds a
    /// real SUISA declaration, where an empty work title would be a genuine
    /// compliance problem. Freely editable afterward, same as any other
    /// field. `cueNumber` is 1-indexed, matching the same display position
    /// `CueTableRow.number`/the waveform's "CUE N" label already use.
    public static func defaultTitle(projectTitle: String, cueNumber: Int) -> String {
        "\(projectTitle)_Score_Cue-\(cueNumber)"
    }

    /// Auto-assigns the project's existing Komponist*in/Arrangeur*in rosters
    /// (`Person.intendedRoles`, D7) to a freshly-created cue — two
    /// independent role pools, each split per `splitShares(role:personIDs:)`
    /// below. Author/Publisher/Performer are never auto-assigned (fully
    /// manual, unaffected) — `PersonIntendedRole` itself has no case for
    /// either of the first two, and `.performer`'s own roster is
    /// deliberately excluded here even though the case exists, since
    /// performer rows are informational-only and never part of any share
    /// pool (SPEC.md §2.2/§4.4).
    public static func defaultRightHolders(people: [Person]) -> [CueRightHolder] {
        splitShares(role: .composer, personIDs: people.filter { $0.intendedRoles.contains(.composer) }.map(\.id))
            + splitShares(role: .arranger, personIDs: people.filter { $0.intendedRoles.contains(.arranger) }.map(\.id))
    }

    /// One role's independent 100% pool, split across `personIDs` in array
    /// order: `100 / N` (integer percent) each, with the *first-listed*
    /// person absorbing any remainder from uneven division — e.g. 3 people
    /// → 34/33/33, not 33/33/34. Both `performanceBroadcastShare` and
    /// `mechanicalRightsShare` get the identical computed percentage, since
    /// nothing distinguishes the two for the same set of people in the same
    /// role. Returns `[]` for an empty roster — nothing to split.
    private static func splitShares(role: CueRightHolderRole, personIDs: [Person.ID]) -> [CueRightHolder] {
        guard !personIDs.isEmpty else { return [] }
        let count = personIDs.count
        let base = 100 / count
        let remainder = 100 - base * count
        return personIDs.enumerated().map { index, personID in
            let share = Decimal(base + (index == 0 ? remainder : 0))
            return CueRightHolder(
                party: .person(personID),
                role: role,
                performanceBroadcastShare: share,
                mechanicalRightsShare: share
            )
        }
    }
}

/// Not `public`: shared, module-internal convenience for the two real
/// cue-creation points, `DetectCuesUseCase` and `UpdateCueUseCase.split`.
extension Cue {
    func autoPopulated(cueNumber: Int, projectTitle: String, people: [Person]) -> Cue {
        Cue(
            id: id,
            title: CueAutoPopulation.defaultTitle(projectTitle: projectTitle, cueNumber: cueNumber),
            workNumber: workNumber,
            duration: duration,
            rightHolders: CueAutoPopulation.defaultRightHolders(people: people),
            isArrangementOfProtectedOriginal: isArrangementOfProtectedOriginal,
            source: source,
            startTimecode: startTimecode,
            notes: notes
        )
    }
}
