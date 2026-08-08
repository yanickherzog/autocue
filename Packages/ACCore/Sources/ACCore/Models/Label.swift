import Foundation

/// A corporate right-holder or production contact (publisher, production
/// company, broadcaster) — the "...or publishing company" half of the SUISA
/// form's combined name field (SPEC.md §4.5). Contrast with `Person`.
///
/// Referenced elsewhere only via `Party.label(Label.ID)` — never copied
/// field-by-field into `Setup`/`CueRightHolder` (`CLAUDE.md`, "Single Source
/// of Truth").
public struct Label: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let address: PostalAddress
    public let ipiNumber: String?
    public let kind: LabelKind?

    public init(
        id: UUID = UUID(),
        name: String,
        address: PostalAddress,
        ipiNumber: String? = nil,
        kind: LabelKind? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.ipiNumber = ipiNumber
        self.kind = kind
    }
}

/// App-internal grouping for a `Label`, used only for UI organization — not a
/// field on the SUISA form itself (SPEC.md §4.5).
public enum LabelKind: Equatable, Sendable {
    case publisher
    case productionCompany
    case broadcaster
    case other
}
