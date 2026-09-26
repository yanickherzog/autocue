import ACCore

/// Turns `ValidateCueRightHolderSharesUseCase`'s issue list into concrete,
/// human-readable strings for `CueRowDetailView`'s warning alert
/// (`ROADMAP.md` D10) — naming precisely what failed (which pool and its
/// real total, or which right-holder is missing which attachment) instead of
/// one fixed, generic sentence.
///
/// **Real bug this replaces, confirmed with actual runtime evidence before
/// this fix was written:** the previous alert always showed the same
/// hardcoded "pool doesn't sum to 100%" text whenever `validate()` returned
/// *any* issue — including `.missingPublishingContractAttachment`, which has
/// nothing to do with share sums. A cue with two composers and a publisher
/// whose shares genuinely summed to exactly 100% in both pools still showed
/// the share-sum message, because the publisher's "Publishing contract
/// attached" checkbox was unchecked — a real, different issue the alert text
/// misreported. See `docs/DECISIONS.md` for the full investigation.
///
/// A plain, pure, non-View type — not a View or ViewModel — specifically so
/// this formatting logic is unit-testable; `CueRowDetailView` itself, like
/// every other View in this codebase, isn't (`CONTRIBUTING.md` §5/§7).
/// Party-name resolution goes through `PartyResolver` (`ACCore`), the same
/// lookup `CueRightHolderEditorView`'s own `resolvedName` already uses — no
/// second, ad hoc name-resolution path.
enum CueRightHolderValidationMessageFormatter {
    /// One message per issue, in the same order `validate()` returned them —
    /// **every** issue gets its own message, never just the first, so a
    /// second, unrelated problem isn't discovered only on a later "Done"
    /// press.
    static func messages(
        for issues: [CueRightHolderValidationIssue],
        rightHolders: [CueRightHolder],
        people: [Person],
        labels: [Label]
    ) -> [String] {
        issues.map { issue in
            switch issue {
            case let .performanceBroadcastSharesDoNotSumTo100(pool, total):
                "Broadcast shares for \(poolDescription(pool)) sum to \(total)%, not 100%."
            case let .mechanicalRightsSharesDoNotSumTo100(pool, total):
                "Mechanical shares for \(poolDescription(pool)) sum to \(total)%, not 100%."
            case let .missingPublishingContractAttachment(index):
                "\(name(at: index, in: rightHolders, people: people, labels: labels)) " +
                    "is missing \"Publishing contract attached.\""
            case let .missingArrangementAuthorization(index):
                "\(name(at: index, in: rightHolders, people: people, labels: labels)) " +
                    "is missing \"Arrangement authorization attached.\""
            }
        }
    }

    private static func poolDescription(_ pool: CueRightHolderSharePool) -> String {
        switch pool {
        case .creatorAndPublisher: "the combined Composer/Author/Publisher pool"
        case .arranger: "the Arranger pool"
        }
    }

    private static func name(
        at index: Int,
        in rightHolders: [CueRightHolder],
        people: [Person],
        labels: [Label]
    ) -> String {
        guard rightHolders.indices.contains(index) else { return "A right-holder" }
        let party = rightHolders[index].party
        return PartyResolver.resolve(party, people: people, labels: labels)?.displayName ?? "Unknown"
    }
}
