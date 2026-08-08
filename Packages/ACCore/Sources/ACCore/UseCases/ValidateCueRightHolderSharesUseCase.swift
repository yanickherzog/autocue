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
public enum ValidateCueRightHolderSharesUseCase {
    /// Every issue currently present on `cue`, or an empty array if it's
    /// fully valid. Order is not significant.
    public static func validate(_ cue: Cue) -> [CueRightHolderValidationIssue] {
        var issues: [CueRightHolderValidationIssue] = []

        let performanceBroadcastTotal = cue.rightHolders.reduce(Decimal(0)) { $0 + $1.performanceBroadcastShare }
        if performanceBroadcastTotal != 100 {
            issues.append(.performanceBroadcastSharesDoNotSumTo100(total: performanceBroadcastTotal))
        }

        let mechanicalRightsTotal = cue.rightHolders.reduce(Decimal(0)) { $0 + $1.mechanicalRightsShare }
        if mechanicalRightsTotal != 100 {
            issues.append(.mechanicalRightsSharesDoNotSumTo100(total: mechanicalRightsTotal))
        }

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
}

/// One reason a `Cue`'s right-holders fail SPEC.md §4.4/§4.6 validation.
///
/// `rightHolderIndex` identifies the offending row by its position in
/// `Cue.rightHolders` — `CueRightHolder` itself has no `id` field to
/// reference instead (SPEC.md §4.4).
public enum CueRightHolderValidationIssue: Equatable, Sendable {
    case performanceBroadcastSharesDoNotSumTo100(total: Decimal)
    case mechanicalRightsSharesDoNotSumTo100(total: Decimal)
    case missingPublishingContractAttachment(rightHolderIndex: Int)
    case missingArrangementAuthorization(rightHolderIndex: Int)
}
