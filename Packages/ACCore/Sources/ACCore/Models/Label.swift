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
    /// **Never exported to the SUISA document; not a SUISA field at all.** A
    /// UI-organizing hint only — whether this `Label` has been added to the
    /// Setup screen's standalone "Label" roster bucket, the exact same
    /// concept `Person.intendedRoles` already establishes for
    /// Komponist*in/Arrangeur*in/Interpret*in, applied to `Label`'s one
    /// equivalent roster (there's only ever one, unlike `Person`'s three, so
    /// a plain `Bool` — not a `Set<Enum>` — is proportionate; `CLAUDE.md`
    /// rule 7). Set automatically when a brand-new `Label` is created from
    /// that bucket's own picker, or when an *existing* `Label` is explicitly
    /// selected there — never inferred from any other context (creating or
    /// selecting a `Label` via Producer*in's picker, for instance, never
    /// sets this). This is what keeps the standalone Label bucket showing
    /// only `Label`s actually intended for it, instead of every `Label` in
    /// the project's directory regardless of where it was created — see
    /// `docs/DECISIONS.md`.
    public let intendedForLabelRoster: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        address: PostalAddress,
        ipiNumber: String? = nil,
        kind: LabelKind? = nil,
        intendedForLabelRoster: Bool = false
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.ipiNumber = ipiNumber
        self.kind = kind
        self.intendedForLabelRoster = intendedForLabelRoster
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
