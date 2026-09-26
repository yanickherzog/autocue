import Foundation

/// Checks a single `Cue`'s right-holder rows against the SUISA-mapped
/// cross-field rules in SPEC.md §4.4/§4.6.
///
/// A pure function of a `Cue` value with no Repository dependency — the same
/// "pure static helper" shape SPEC.md §4.14 describes for
/// `RecalculateTotalMusicRuntimeUseCase`, and the same enum-namespace idiom
/// SPEC.md §4.13 specifies for `PartyResolver`. Unlike Use Cases further down
/// the roadmap that wrap a Repository, there's nothing here to construct or
/// inject.
///
/// **Two independent pools, not one per role — corrected at D10, third
/// round, per SUISA's own Verteilungsreglement (distribution rules), not
/// just the D10-second-round model this replaces.** The second-round version
/// of this rule treated every non-`.performer` role (Composer, Author,
/// Arranger, Publisher) as its own fully independent 100% pool — a real fix
/// over the original D2 combined-pool bug, but itself still wrong for
/// Publisher: a publisher's share is carved out of what would otherwise go
/// to the writers, not an independent, additional 100% of its own. The
/// correct model, confirmed directly against SUISA's own distribution rules:
/// **Composer, Author, and Publisher combine into one shared 100% pool**
/// (`CueRightHolderSharePool.creatorAndPublisher`); **Arranger remains its
/// own, genuinely separate 100% pool** (`.arranger`), exactly as the
/// second-round model already had it — that part was already correct and is
/// unchanged. See `docs/DECISIONS.md` for the full account.
public enum ValidateCueRightHolderSharesUseCase {
    /// `.author`/`.publisher` combine with `.composer` into one pool;
    /// `.arranger` is checked separately, below. `.performer` has no pool at
    /// all — SUISA's WA Film form has no percentage-share column for
    /// performers (the C/A/AR/E legend is composer/author/arranger/publisher
    /// only); see `CueRightHolderRole`'s doc comment.
    private static let creatorAndPublisherRoles: Set<CueRightHolderRole> = [.composer, .author, .publisher]

    /// Every issue currently present on `cue`, or an empty array if it's
    /// fully valid. Order is not significant.
    public static func validate(_ cue: Cue) -> [CueRightHolderValidationIssue] {
        var issues: [CueRightHolderValidationIssue] = []

        let creatorAndPublisherGroup = cue.rightHolders.filter { creatorAndPublisherRoles.contains($0.role) }
        issues.append(contentsOf: shareIssues(in: creatorAndPublisherGroup, pool: .creatorAndPublisher))

        let arrangerGroup = cue.rightHolders.filter { $0.role == .arranger }
        issues.append(contentsOf: shareIssues(in: arrangerGroup, pool: .arranger))

        for (index, rightHolder) in cue.rightHolders.enumerated() {
            if rightHolder.role == .publisher, !rightHolder.publishingContractAttached {
                issues.append(.missingPublishingContractAttachment(rightHolderIndex: index))
            }

            let isUnauthorizedArrangement = rightHolder.role == .arranger
                && cue.isArrangementOfProtectedOriginal
                && !rightHolder.arrangementAuthorizationAttached
            if isUnauthorizedArrangement {
                issues.append(.missingArrangementAuthorization(rightHolderIndex: index))
            }
        }

        return issues
    }

    /// A pool with zero members has nothing to validate at all — this is
    /// what makes "one composer at 100%, one arranger at 100%" (with no
    /// author/publisher present) correctly pass: the creator/publisher pool
    /// is checked only against whichever of its three roles actually have
    /// members, never combined with arranger's pool.
    private static func shareIssues(
        in group: [CueRightHolder],
        pool: CueRightHolderSharePool
    ) -> [CueRightHolderValidationIssue] {
        guard !group.isEmpty else { return [] }
        var issues: [CueRightHolderValidationIssue] = []

        let performanceBroadcastTotal = group.reduce(Decimal(0)) { $0 + $1.performanceBroadcastShare }
        if performanceBroadcastTotal != 100 {
            issues.append(.performanceBroadcastSharesDoNotSumTo100(pool: pool, total: performanceBroadcastTotal))
        }

        let mechanicalRightsTotal = group.reduce(Decimal(0)) { $0 + $1.mechanicalRightsShare }
        if mechanicalRightsTotal != 100 {
            issues.append(.mechanicalRightsSharesDoNotSumTo100(pool: pool, total: mechanicalRightsTotal))
        }

        return issues
    }
}

/// Which independent 100% share pool a `Cue`'s right-holders fall into
/// (SPEC.md §4.6) — not one case per `CueRightHolderRole`, since
/// `.composer`/`.author`/`.publisher` share one pool while `.arranger` is
/// its own; see `ValidateCueRightHolderSharesUseCase`'s own doc comment.
public enum CueRightHolderSharePool: Equatable, Sendable {
    case creatorAndPublisher
    case arranger
}

/// One reason a `Cue`'s right-holders fail SPEC.md §4.4/§4.6 validation.
///
/// `rightHolderIndex` identifies the offending row by its position in
/// `Cue.rightHolders` — `CueRightHolder` itself has no `id` field to
/// reference instead (SPEC.md §4.4).
public enum CueRightHolderValidationIssue: Equatable, Sendable {
    /// `pool` identifies *which* pool failed to sum to 100% — carries a
    /// `CueRightHolderSharePool`, not a `CueRightHolderRole`, since D10's
    /// third round corrected the model from one-pool-per-role to two pools
    /// spanning multiple roles. See this type's own file-level doc comment.
    case performanceBroadcastSharesDoNotSumTo100(pool: CueRightHolderSharePool, total: Decimal)
    case mechanicalRightsSharesDoNotSumTo100(pool: CueRightHolderSharePool, total: Decimal)
    case missingPublishingContractAttachment(rightHolderIndex: Int)
    case missingArrangementAuthorization(rightHolderIndex: Int)
}
