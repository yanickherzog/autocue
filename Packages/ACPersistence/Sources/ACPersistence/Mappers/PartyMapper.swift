import ACCore
import Foundation

/// Encodes/decodes `ACCore.Party` to/from the flat kind+id pair every
/// `Party`-typed SwiftData column pair uses (`SetupEntity.producerPartyKind`/
/// `.producerPartyID`, `CueRightHolderEntity.partyKind`/`.partyID`, etc.).
///
/// Centralized here so the 4+ call sites (`Setup.producer`/
/// `.directorOrPrincipal`/`.declarant`, `CueRightHolder.party`) don't each
/// reimplement the same encode/decode — and, more importantly, so there's
/// exactly one place that could ever be tempted to turn this into a real
/// `@Relationship` instead. Deliberately never a `@Relationship`: SPEC.md
/// §4.12's delete guard (`DeleteRightHolderUseCase`, built in `ACCore`)
/// already assumes bare-UUID references with no SwiftData cascade/nullify
/// behavior behind them. Introducing a real relationship here would let
/// SwiftData silently nullify or cascade-delete across a reference the
/// delete guard has no way to know about, undermining the entire reason that
/// guard exists.
enum PartyMapper {
    private static let personKind = "person"
    private static let labelKind = "label"

    static func kind(for party: Party) -> String {
        switch party {
        case .person: personKind
        case .label: labelKind
        }
    }

    static func id(for party: Party) -> UUID {
        switch party {
        case let .person(id): id
        case let .label(id): id
        }
    }

    /// Throws if `kind` isn't a recognized value — this indicates persisted
    /// data corruption (a hand-edited store, a future schema mistake), not a
    /// normal runtime condition, so it's surfaced as an error rather than
    /// silently defaulting to one case.
    static func party(kind: String, id: UUID) throws -> Party {
        switch kind {
        case personKind: .person(id)
        case labelKind: .label(id)
        default: throw MappingError.unknownPartyKind(kind)
        }
    }

    // MARK: - Optional overloads

    /// `Setup.declarant` is `Party?`, not `Party` (see `docs/DECISIONS.md`,
    /// "`Setup`'s three `Party` fields become optional") — a brand-new
    /// `Project` genuinely has none chosen yet. `producer`/
    /// `.directorOrPrincipal` used to share this shape too; now `[Party]`,
    /// they use the array overloads below instead. These overloads let
    /// `SetupMapper` reuse the same encode/decode logic above instead of
    /// duplicating it with `if let` at every call site; `CueRightHolder.party`
    /// stays non-optional (always required) and keeps using the non-optional
    /// overloads above unchanged.
    static func kind(for party: Party?) -> String? {
        party.map(kind(for:))
    }

    static func id(for party: Party?) -> UUID? {
        party.map(id(for:))
    }

    /// `nil` iff both `kind`/`id` are `nil` (nothing was ever set). A
    /// mismatched pair (one `nil`, one not) is the same persisted-data-
    /// corruption case the non-optional overload guards against, not a
    /// normal "unset" state, so it still throws rather than silently
    /// treating a partial pair as absent.
    static func party(kind: String?, id: UUID?) throws -> Party? {
        switch (kind, id) {
        case (nil, nil):
            nil
        case let (kind?, id?):
            try party(kind: kind, id: id)
        default:
            throw MappingError.unknownPartyKind(kind ?? "<nil>")
        }
    }

    // MARK: - Array overloads

    /// `Setup.producer`/`.directorOrPrincipal` are `[Party]`, not `Party?`
    /// (`ROADMAP.md` D7, later round — see `docs/DECISIONS.md`) — one or
    /// more, order-preserving. Stored as two parallel `[String]`/`[UUID]`
    /// columns (`SetupEntity.producerPartyKinds`/`.producerPartyIDs`, same
    /// for director), the same "raw values as `[String]`" pattern
    /// `SetupEntity` already uses for `Set<ProductionType>` et al., extended
    /// with a second parallel array since a `Party` needs two components
    /// (kind + id) per element, not one.
    static func kinds(for parties: [Party]) -> [String] {
        parties.map(kind(for:))
    }

    static func ids(for parties: [Party]) -> [UUID] {
        parties.map(id(for:))
    }

    /// Throws if `kinds`/`ids` have different lengths (a corrupt pairing —
    /// the two arrays are only ever written together, atomically, by
    /// `kinds(for:)`/`ids(for:)` above) or if any individual pair fails to
    /// decode (see the non-optional `party(kind:id:)` overload).
    static func parties(kinds: [String], ids: [UUID]) throws -> [Party] {
        guard kinds.count == ids.count else {
            throw MappingError.mismatchedPartyArrayLengths(kindsCount: kinds.count, idsCount: ids.count)
        }
        return try zip(kinds, ids).map { try party(kind: $0, id: $1) }
    }
}

enum MappingError: Error, Equatable {
    case unknownPartyKind(String)
    case unknownRawValue(type: String, rawValue: String)
    case corruptWaveformPeaksData(expectedCount: Int, actualMinCount: Int, actualMaxCount: Int)
    case missingRequiredChild(type: String, parentID: UUID)
    case mismatchedPartyArrayLengths(kindsCount: Int, idsCount: Int)
}
