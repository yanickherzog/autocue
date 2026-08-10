import Foundation

/// "Sendedatum" ("Sender, Sendung, Datum der Sendung") — a specific
/// broadcaster/programme/date a production aired or is scheduled to air on
/// (SPEC.md §4.2). Deliberately separate from `Setup.knownOrFutureBroadcasts`
/// (free-text, covers the same general "broadcasts/screenings" territory) —
/// this is real, structured data one specific broadcast, not a loose note.
///
/// All three sub-fields optional: none is on the physical SUISA form this
/// project targets, and a value can be partially known (a confirmed
/// broadcaster before an exact air date is set) — same reasoning as
/// `PostalAddress`'s all-required fields being the exception, not the norm,
/// for this project's value types.
///
/// No `id` field: `BroadcastDetails` has no independent identity outside the
/// one `Setup` that holds it, the same "no `id` field, no `Identifiable`"
/// shape as `PostalAddress`/`Party` (`CLAUDE.md`, "Domain Model Value-Type
/// Conformances").
///
/// **Export-required-ness unresolved as of D7 planning** — see
/// `ExploitationType`'s doc comment; the same flag applies here, confirm
/// against the real SUISA form at `ROADMAP.md` D11/T11.3.
public struct BroadcastDetails: Equatable, Sendable {
    /// "Sender" — the broadcaster's name.
    public let broadcaster: String?
    /// "Sendung" — the programme/show name.
    public let programmeName: String?
    /// "Datum der Sendung" — the broadcast date.
    public let date: Date?

    public init(broadcaster: String? = nil, programmeName: String? = nil, date: Date? = nil) {
        self.broadcaster = broadcaster
        self.programmeName = programmeName
        self.date = date
    }
}
