import Foundation

/// A complete postal address — used wherever the SUISA form requires "complete
/// address" for a `Person`/`Label` (SPEC.md §4.5). All four parts are required
/// whenever a `PostalAddress` is present at all; there's no partial-address case.
public struct PostalAddress: Equatable, Sendable {
    public let street: String
    public let postalCode: String
    public let city: String
    public let country: String

    public init(street: String, postalCode: String, city: String, country: String) {
        self.street = street
        self.postalCode = postalCode
        self.city = city
        self.country = country
    }
}

public extension PostalAddress {
    /// Whether all four parts are actually filled in, not merely present as
    /// non-`nil` — the SUISA form's "complete address" requirement (SPEC.md
    /// §4.5) means all four non-blank, not just a `PostalAddress` value
    /// existing (its fields are already non-optional `String`, so a blank
    /// value is otherwise indistinguishable from a real one at the type level).
    var isComplete: Bool {
        !street.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !postalCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
