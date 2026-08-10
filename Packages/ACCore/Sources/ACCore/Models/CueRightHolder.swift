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
/// (composer / author / arranger / publisher), SPEC.md §4.4, plus
/// `.performer` ("Interpret*in").
///
/// `.performer` is **informational only within AutoCue** — SUISA's WA Film
/// form has no percentage-share slot for performers (the C/A/AR/E legend and
/// its two share columns are composer/author/arranger/publisher only); real
/// performer royalty reporting is SWISSPERFORM's own separate, self-service
/// process (SPEC.md §2.2). A `.performer` row's `performanceBroadcastShare`/
/// `mechanicalRightsShare` are therefore excluded from
/// `ValidateCueRightHolderSharesUseCase`'s two 100%-sum checks, and
/// `.performer` rows are excluded from the PDF export's SUISA-form rendering
/// (no slot for a 5th role there) while still appearing in the XLSX export —
/// see `docs/DECISIONS.md` for the full reasoning behind adding this case,
/// which reverses SPEC.md §2.2's original performer-exclusion decision.
///
/// `CaseIterable`: added alongside `.performer` specifically so
/// `CueRightHolderMapper`'s round-trip can be tested exhaustively — every
/// other raw-value-mapped enum in this codebase (`ProductionType`,
/// `AttachmentType`, `TimecodeFrameRate`) already has it for the same reason.
public enum CueRightHolderRole: Equatable, Sendable, CaseIterable {
    case composer
    case author
    case arranger
    case publisher
    case performer
}
