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
    /// A UI-organizing hint only — see `PersonIntendedRole`'s own doc
    /// comment. Never exported, never used to default a `Cue`-level
    /// `CueRightHolder.role` (SPEC.md §4.5).
    public let intendedRole: PersonIntendedRole?

    public init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        ipiNumber: String? = nil,
        address: PostalAddress? = nil,
        email: String? = nil,
        swissPerformNumber: String? = nil,
        intendedRole: PersonIntendedRole? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.ipiNumber = ipiNumber
        self.address = address
        self.email = email
        self.swissPerformNumber = swissPerformNumber
        self.intendedRole = intendedRole
    }
}

/// Which of the Setup screen's collaborator-roster buckets a `Person` was
/// added under (`ROADMAP.md` D7) — Komponist*in/Arrangeur*in/Interpret*in.
/// Purely a directory-level UI memory aid: it exists so those three roster
/// sections can each show only the people added under them, instead of one
/// undifferentiated list where (for example) a director's name could appear
/// mixed in with composers. **Not exported, and not the same thing as**
/// `CueRightHolderRole` (SPEC.md §4.4) — that's a real, exported, per-Cue,
/// per-right-holder assignment made explicitly at D10; this is neither
/// exported nor per-Cue, and setting it never assigns or defaults a
/// `CueRightHolder.role`. Deliberately a smaller case set than
/// `CueRightHolderRole` — no `.author`/`.publisher`, since those two roles'
/// own SUISA-form legend letters (A/E) don't correspond to anything this
/// screen's brief asked for as a roster bucket.
public enum PersonIntendedRole: Equatable, Sendable, CaseIterable {
    case composer
    case arranger
    case performer
}
