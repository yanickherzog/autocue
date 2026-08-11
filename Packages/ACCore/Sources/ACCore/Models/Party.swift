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
///
/// `Hashable`, per `CLAUDE.md`'s conformance policy ("added only where a
/// type is genuinely used as a `Set` element, ... or needs SwiftUI list/
/// selection identity") — `Setup.producer`/`.directorOrPrincipal` becoming
/// `[Party]` (`ROADMAP.md` D7) needs `ForEach(parties, id: \.self)` identity
/// in `SetupView`'s multi-entry rows; see `docs/DECISIONS.md`.
public enum Party: Equatable, Hashable, Sendable {
    case person(UUID)
    case label(UUID)
}
