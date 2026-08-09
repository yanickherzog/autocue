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
@Model
final class LabelEntity {
    @Attribute(.unique) var id: UUID
    var order: Int
    var name: String
    var addressStreet: String
    var addressPostalCode: String
    var addressCity: String
    var addressCountry: String
    var ipiNumber: String?
    var kind: String?

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
        kind: String?
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
        project = nil
    }
}
