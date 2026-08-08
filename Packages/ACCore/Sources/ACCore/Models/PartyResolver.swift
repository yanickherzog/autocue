import Foundation

/// Resolves a `Party` value into displayable data (name, address) by looking
/// it up against `Project.people`/`Project.labels` — the single place this
/// scan-and-match logic lives, so it isn't reimplemented slightly differently
/// in every ViewModel that needs to show a right-holder (SPEC.md §4.13).
///
/// A stateless, pure (no I/O, no async) namespace, not a Use Case — it has no
/// Repository dependency and nothing to orchestrate (`CLAUDE.md`, Naming
/// Conventions).
public enum PartyResolver {
    /// `nil` only if `party`'s referenced `id` isn't found in either `people`
    /// or `labels` — i.e. exactly the dangling-reference case
    /// `DeleteRightHolderUseCase` (SPEC.md §4.12) exists to prevent. Any
    /// caller that hits `nil` here, once that guard is correctly enforced
    /// everywhere deletion happens, indicates a bug, not a valid state to
    /// design UI around.
    public static func resolve(_ party: Party, people: [Person], labels: [Label]) -> ResolvedParty? {
        switch party {
        case let .person(id):
            guard let person = people.first(where: { $0.id == id }) else { return nil }
            return ResolvedParty(
                displayName: "\(person.firstName) \(person.lastName)",
                address: person.address,
                ipiNumber: person.ipiNumber
            )
        case let .label(id):
            guard let label = labels.first(where: { $0.id == id }) else { return nil }
            return ResolvedParty(
                displayName: label.name,
                address: label.address,
                ipiNumber: label.ipiNumber
            )
        }
    }
}

/// A `Party` resolved to displayable data (SPEC.md §4.13).
///
/// `Sendable` fills a gap in SPEC.md §4.13's illustrative snippet (which
/// shows only `Equatable`) — required unconditionally by `CLAUDE.md`,
/// "Domain Model Value-Type Conformances," since resolved values can cross a
/// Repository `AsyncStream`/`AsyncThrowingStream` boundary the same as any
/// other `ACCore` value type.
public struct ResolvedParty: Equatable, Sendable {
    public let displayName: String
    public let address: PostalAddress?
    public let ipiNumber: String?

    public init(displayName: String, address: PostalAddress?, ipiNumber: String?) {
        self.displayName = displayName
        self.address = address
        self.ipiNumber = ipiNumber
    }
}
