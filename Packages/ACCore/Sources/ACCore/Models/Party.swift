import Foundation

/// A reference to a right-holder or production contact — either an individual
/// (`Person`) or a corporate entity (`Label`). Used for `Setup.producer`,
/// `Setup.directorOrPrincipal`, `Setup.declarant`, `Settings.defaultDeclarant`,
/// and `CueRightHolder.party` (SPEC.md §4.5).
///
/// Not persisted independently — a bare `UUID` reference into `Project.people`/
/// `Project.labels`, resolved to display data via `PartyResolver` (SPEC.md §4.13).
/// Deletion of a referenced `Person`/`Label` is guarded (SPEC.md §4.12).
///
/// The case payloads are plain `UUID`, not `Person.ID`/`Label.ID` — `Person`/
/// `Label` don't exist yet (ROADMAP.md D2). Once they do, both will declare
/// `id: UUID` (SPEC.md §4.5), so `Person.ID`/`Label.ID` resolve to the exact
/// same concrete type already used here; no change needed once D2 lands.
public enum Party: Equatable, Sendable {
    case person(UUID)
    case label(UUID)
}
