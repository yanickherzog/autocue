import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.CueRightHolder` (SPEC.md §4.4).
///
/// `order` is persistence-only, same reasoning as `CueEntity.order` — array
/// order must survive a save/fetch round-trip even though SwiftData gives no
/// to-many fetch-order guarantee and the domain type has no such field.
///
/// `party` is stored as a flat kind+id pair, not a `@Relationship` — see
/// `SetupEntity`'s doc comment and `PartyMapper` for why.
@Model
final class CueRightHolderEntity {
    var order: Int
    var partyKind: String
    var partyID: UUID
    var role: String
    var performanceBroadcastShare: Decimal
    var mechanicalRightsShare: Decimal
    var publishingContractAttached: Bool
    var arrangementAuthorizationAttached: Bool

    var cue: CueEntity?

    init(
        order: Int,
        partyKind: String,
        partyID: UUID,
        role: String,
        performanceBroadcastShare: Decimal,
        mechanicalRightsShare: Decimal,
        publishingContractAttached: Bool,
        arrangementAuthorizationAttached: Bool
    ) {
        self.order = order
        self.partyKind = partyKind
        self.partyID = partyID
        self.role = role
        self.performanceBroadcastShare = performanceBroadcastShare
        self.mechanicalRightsShare = mechanicalRightsShare
        self.publishingContractAttached = publishingContractAttached
        self.arrangementAuthorizationAttached = arrangementAuthorizationAttached
        cue = nil
    }
}
