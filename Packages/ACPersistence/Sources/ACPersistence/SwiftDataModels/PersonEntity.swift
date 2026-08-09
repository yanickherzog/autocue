import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.Person` (SPEC.md §4.5).
///
/// `PostalAddress` is flattened into four optional scalar columns rather than
/// given its own entity. This is safe specifically because `PostalAddress`'s
/// optionality is all-or-nothing at the domain level (SPEC.md §4.5: "all four
/// parts are required whenever a `PostalAddress` is present at all") —
/// `PersonMapper` always writes either four real strings or four `nil`s, so a
/// partial state can never legitimately arise from a domain round-trip.
///
/// `order` is persistence-only, same reasoning as `CueEntity.order`:
/// `Project.people` is a plain `[Person]` array, and `Project`'s synthesized
/// `Equatable` conformance compares it order-sensitively, but SwiftData gives
/// no fetch-order guarantee for a to-many relationship — confirmed the hard
/// way, by an actual non-deterministic round-trip test failure across runs
/// before this field was added, not anticipated up front.
///
/// **No `@Attribute(.unique)` on `id`, deliberately.** Nothing in
/// `ProjectRepositoryImpl` ever queries a `PersonEntity` by `id` directly —
/// `Person`/`Label` are only ever reached by walking `ProjectEntity.people`/
/// `.labels`, never fetched independently — so a uniqueness constraint here
/// enforces nothing this Deliverable actually needs (`CLAUDE.md` rule 7).
/// Was present in an earlier revision of this type; removed as a candidate
/// fix for a real SIGTRAP crash on PR #4's CI run. **It turned out not to be
/// the actual cause** (see `docs/DECISIONS.md` for the real one — a Swift
/// exclusivity violation in the mappers) — kept anyway, since it's correct
/// on its own merits independent of that crash.
@Model
final class PersonEntity {
    var id: UUID
    var order: Int
    var firstName: String
    var lastName: String
    var ipiNumber: String?
    var addressStreet: String?
    var addressPostalCode: String?
    var addressCity: String?
    var addressCountry: String?
    var email: String?
    var swissPerformNumber: String?

    var project: ProjectEntity?

    init(
        id: UUID,
        order: Int,
        firstName: String,
        lastName: String,
        ipiNumber: String?,
        addressStreet: String?,
        addressPostalCode: String?,
        addressCity: String?,
        addressCountry: String?,
        email: String?,
        swissPerformNumber: String?
    ) {
        self.id = id
        self.order = order
        self.firstName = firstName
        self.lastName = lastName
        self.ipiNumber = ipiNumber
        self.addressStreet = addressStreet
        self.addressPostalCode = addressPostalCode
        self.addressCity = addressCity
        self.addressCountry = addressCountry
        self.email = email
        self.swissPerformNumber = swissPerformNumber
        project = nil
    }
}
