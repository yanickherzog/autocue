import Foundation

/// One right-holder row on a `Cue` (SPEC.md §4.4). No `id` field — SPEC's
/// schema doesn't give this sub-entity independent identity the way `Cue`
/// itself has one; same "no `id` field, no `Identifiable`" shape as
/// `PostalAddress`/`Party` (`CLAUDE.md`, "Domain Model Value-Type
/// Conformances").
public struct CueRightHolder: Equatable, Sendable {
    public let party: Party
    public let role: CueRightHolderRole
    public let performanceBroadcastShare: Decimal
    public let mechanicalRightsShare: Decimal
    public let publishingContractAttached: Bool
    public let arrangementAuthorizationAttached: Bool

    public init(
        party: Party,
        role: CueRightHolderRole,
        performanceBroadcastShare: Decimal,
        mechanicalRightsShare: Decimal,
        publishingContractAttached: Bool = false,
        arrangementAuthorizationAttached: Bool = false
    ) {
        self.party = party
        self.role = role
        self.performanceBroadcastShare = performanceBroadcastShare
        self.mechanicalRightsShare = mechanicalRightsShare
        self.publishingContractAttached = publishingContractAttached
        self.arrangementAuthorizationAttached = arrangementAuthorizationAttached
    }
}

/// A right-holder's role on a `Cue` — the SUISA form's C / A / AR / E legend
/// (composer / author / arranger / publisher), SPEC.md §4.4.
public enum CueRightHolderRole: Equatable, Sendable {
    case composer
    case author
    case arranger
    case publisher
}
