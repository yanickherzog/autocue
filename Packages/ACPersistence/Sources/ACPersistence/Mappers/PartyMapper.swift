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
}

enum MappingError: Error, Equatable {
    case unknownPartyKind(String)
    case unknownRawValue(type: String, rawValue: String)
    case corruptWaveformPeaksData(expectedByteCount: Int, actualByteCount: Int)
    case missingRequiredChild(type: String, parentID: UUID)
}
