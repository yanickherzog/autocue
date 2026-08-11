import Foundation
import SwiftData

/// SwiftData-persisted counterpart of one entry in `ACCore.Setup.broadcastDetails:
/// [BroadcastDetails]` (SPEC.md §4.2.4). A real child `@Model` entity with an
/// owning `@Relationship`, not a flat-columns-on-`SetupEntity` encoding —
/// `Setup.broadcastDetails` was originally a single optional instance stored as
/// three flat columns directly on `SetupEntity`, but that shape can't represent
/// more than one entry; reversed to a proper to-many relationship the same way
/// `CueEntity.rightHolders`/`ProjectEntity.cues` already are, once
/// `Setup.broadcastDetails` itself became `[BroadcastDetails]` (`docs/DECISIONS.md`).
///
/// `order` is persistence-only, same reasoning as `CueEntity.order`/
/// `CueRightHolderEntity.order` — the domain type has no such field; entry order
/// must still survive a save/fetch round-trip despite SwiftData giving no
/// to-many fetch-order guarantee.
@Model
final class BroadcastDetailsEntity {
    var order: Int
    var broadcaster: String?
    var programmeName: String?
    var date: Date?

    var setup: SetupEntity?

    init(order: Int, broadcaster: String?, programmeName: String?, date: Date?) {
        self.order = order
        self.broadcaster = broadcaster
        self.programmeName = programmeName
        self.date = date
        setup = nil
    }
}
