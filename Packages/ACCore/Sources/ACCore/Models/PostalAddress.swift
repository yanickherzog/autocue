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
