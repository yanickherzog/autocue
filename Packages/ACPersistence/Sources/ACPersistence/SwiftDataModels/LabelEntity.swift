import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.Label` (SPEC.md §4.5).
///
/// `address` is flattened (required, non-optional at the domain level too —
/// unlike `PersonEntity`'s optional address, no all-or-nothing ambiguity to
/// guard against here).
///
/// `order` is persistence-only — see `PersonEntity`'s doc comment; the same
/// array-order problem applies identically to `Project.labels`.
///
/// No `@Attribute(.unique)` on `id` — see `PersonEntity`'s doc comment for
/// why (kept on its own merits; it wasn't the cause of the crash it was
/// originally a candidate fix for — see `docs/DECISIONS.md`).
@Model
final class LabelEntity {
    var id: UUID
    var order: Int
    var name: String
    var addressStreet: String
    var addressPostalCode: String
    var addressCity: String
    var addressCountry: String
    var ipiNumber: String?
    var kind: String?
    /// `ACCore.Label.intendedForLabelRoster` — see that field's own doc
    /// comment. A flat `Bool` column — unlike `Person.intendedRoles`
    /// (`Set<PersonIntendedRole>`, stored as `[String]` raw values), this is
    /// a single flag, not a set, so no raw-value encoding is needed.
    var intendedForLabelRoster: Bool

    var project: ProjectEntity?

    init(
        id: UUID,
        order: Int,
        name: String,
        addressStreet: String,
        addressPostalCode: String,
        addressCity: String,
        addressCountry: String,
        ipiNumber: String?,
        kind: String?,
        intendedForLabelRoster: Bool
    ) {
        self.id = id
        self.order = order
        self.name = name
        self.addressStreet = addressStreet
        self.addressPostalCode = addressPostalCode
        self.addressCity = addressCity
        self.addressCountry = addressCountry
        self.ipiNumber = ipiNumber
        self.kind = kind
        self.intendedForLabelRoster = intendedForLabelRoster
        project = nil
    }
}
