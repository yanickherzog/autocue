import Foundation

/// An individual right-holder or production contact — the "name, first name"
/// half of the SUISA form's "name, first name or publishing company" field
/// (SPEC.md §4.5). Contrast with `Label`, the corporate equivalent.
///
/// Referenced elsewhere only via `Party.person(Person.ID)` — never copied
/// field-by-field into `Setup`/`CueRightHolder` (`CLAUDE.md`, "Single Source
/// of Truth").
public struct Person: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let firstName: String
    public let lastName: String
    public let ipiNumber: String?
    public let address: PostalAddress?
    public let email: String?
    public let swissPerformNumber: String?

    public init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        ipiNumber: String? = nil,
        address: PostalAddress? = nil,
        email: String? = nil,
        swissPerformNumber: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.ipiNumber = ipiNumber
        self.address = address
        self.email = email
        self.swissPerformNumber = swissPerformNumber
    }
}
