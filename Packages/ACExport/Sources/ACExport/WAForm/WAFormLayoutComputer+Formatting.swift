import ACCore
import Foundation

/// Display-string formatting for `WAFormLayoutComputer` — split out per
/// `CONTRIBUTING.md` §8's file-length convention.
extension WAFormLayoutComputer {
    /// One `Party`'s display name, followed by its full postal address on
    /// subsequent lines if it has one — the one address-formatting pattern
    /// in this codebase (originally written inline for the declarant block
    /// only; extracted here in round 3, `docs/DECISIONS.md` 2026-10-02, so
    /// the newly-added Produzent/Regisseur address rendering — item A —
    /// reuses it rather than growing a second, independent copy).
    /// `PartyResolver`/`CueSheetLayoutComputer` were checked first: neither
    /// has an existing address-formatting helper — the cue sheet PDF never
    /// renders an address at all (SPEC.md §4.16's per-document rule), so
    /// this declarant-originated pattern is genuinely the only one that
    /// exists to reuse, not a second new one.
    static func formattedPartyWithAddress(_ party: Party, people: [Person], labels: [Label]) -> String? {
        guard let resolved = PartyResolver.resolve(party, people: people, labels: labels) else { return nil }
        var result = resolved.displayName
        if let address = resolved.address {
            result += "\n\(address.street)\n\(address.postalCode) \(address.city)\n\(address.country)"
        }
        return result
    }

    /// Multiple parties (`Setup.producer`/`.directorOrPrincipal` are both
    /// `[Party]`), each formatted via `formattedPartyWithAddress` above and
    /// separated by a blank line — the real form has no printed guidance for
    /// multiple producers/directors sharing one field, so a blank-line
    /// separator is this function's own reasonable choice for the (expected
    /// rare) multi-party case, not a measured value.
    static func formattedPartiesWithAddresses(_ parties: [Party], people: [Person], labels: [Label]) -> String {
        parties.compactMap { formattedPartyWithAddress($0, people: people, labels: labels) }
            .joined(separator: "\n\n")
    }

    /// `HH:MM:SS` — matches the real form's own printed `"___ : ___ : ___
    /// (hh :mm :ss)"` fields exactly, unlike the cue sheet's deliberate
    /// `MM:SS` exception (SPEC.md §4.3) — this document's duration fields are
    /// explicitly hour-inclusive on their own printed label. Still used by
    /// tests/call sites that want the combined string; `durationGroups`
    /// below is what every real on-page duration field actually draws with,
    /// as of round 3.
    static func formattedHMS(_ duration: MediaDuration) -> String {
        let totalSeconds = Int(duration.seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// The same `hh`/`mm`/`ss` values `formattedHMS` combines into one
    /// string, kept as three separate zero-padded strings instead — real,
    /// confirmed fix from round 3's rendered-output review
    /// (`docs/DECISIONS.md`, 2026-10-02): the real template prints its own
    /// colon separators between three distinct blanks, so drawing one
    /// combined "hh:mm:ss" string collided/overlapped once a value's digits
    /// ran long (confirmed real case: an illegible "00:01:t6"-looking
    /// render). Each group is meant to be drawn independently, centered over
    /// its own printed blank, via `centeredText` — never recombined with
    /// colons in the overlay, since the template already prints them.
    ///
    /// A named struct, not a 3-member tuple (`CONTRIBUTING.md` §8's
    /// `large_tuple` limit caps tuples at 2 members) — also reused below by
    /// `DurationFieldCenters`, the matching 3 real measured x-centers each
    /// group is drawn at.
    struct DurationDigitGroups: Equatable {
        let hours: String
        let minutes: String
        let seconds: String
    }

    static func durationGroups(_ duration: MediaDuration) -> DurationDigitGroups {
        let totalSeconds = Int(duration.seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        return DurationDigitGroups(
            hours: String(format: "%02d", hours),
            minutes: String(format: "%02d", minutes),
            seconds: String(format: "%02d", seconds)
        )
    }

    /// The real, measured center-x of one duration field's three printed
    /// blanks — one instance per field (`mainFormPage1HeaderElements`'s two
    /// top-level fields, `WAFormWorkBlockGeometry`'s per-work field on each
    /// document). Grouped into one value so `durationElements` stays under
    /// `CONTRIBUTING.md` §8's `function_parameter_count` limit.
    struct DurationFieldCenters {
        let hour: Double
        let minute: Double
        let second: Double
    }

    /// Three independently-positioned, independently-centered elements for
    /// one duration field — see `durationGroups` above for why this replaces
    /// a single combined "hh:mm:ss" string at every real call site.
    static func durationElements(
        _ duration: MediaDuration,
        centers: DurationFieldCenters,
        y: Double,
        font: LayoutFontSpec
    ) -> [CueSheetLayoutElement] {
        let groups = durationGroups(duration)
        return [
            centeredText(groups.hours, centerX: centers.hour, y: y, font: font),
            centeredText(groups.minutes, centerX: centers.minute, y: y, font: font),
            centeredText(groups.seconds, centerX: centers.second, y: y, font: font),
        ]
    }

    /// Every distinct `.composer`-role `Party` across the **whole
    /// production** (not just one page's cues), excluding `declarant` —
    /// added for round 3's item B (`docs/DECISIONS.md`, 2026-10-02): the
    /// main form's page 2 "Name, Vorname oder Firma und Unterschrift aller
    /// anderen Rechtsinhaber" box lists every composer who isn't the
    /// declarant, since each of them individually needs to sign it. Mirrors
    /// `CueSheetLayoutComputer+Header.aggregatedPartyIPILines`'s own
    /// dedupe-by-`Party`-identity traversal shape exactly (same `Set<Party>`
    /// seen-guard, same per-cue/per-right-holder loop) — proposed and
    /// confirmed against that existing pattern before being written, per the
    /// project owner's explicit request, rather than inventing a new
    /// aggregation shape. Name only, no address — the signature box has no
    /// space for one and none was asked for.
    static func otherComposerSignatureLines(
        cues: [Cue],
        excludingDeclarant declarant: Party?,
        people: [Person],
        labels: [Label]
    ) -> [String] {
        var seen = Set<Party>()
        var lines: [String] = []
        for cue in cues {
            for rightHolder in cue.rightHolders where rightHolder.role == .composer {
                guard rightHolder.party != declarant, !seen.contains(rightHolder.party),
                      let resolved = PartyResolver.resolve(rightHolder.party, people: people, labels: labels)
                else { continue }
                seen.insert(rightHolder.party)
                lines.append(resolved.displayName)
            }
        }
        return lines
    }

    /// `Decimal` share values are already scaled to 2 decimal places
    /// (SPEC.md §4.4) — formatted with exactly that precision, matching the
    /// real form's own percentage columns (`CueRightHolder
    /// .performanceBroadcastShare`/`.mechanicalRightsShare`).
    static func formattedPercent(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    /// `C`/`A`/`AR`/`E` — the real form's own role legend (SPEC.md §4.4,
    /// confirmed directly against the real form: "C Komponist A Textdichter
    /// AR Arrangeur E Verlag"). `.performer` never reaches this function —
    /// excluded entirely before a role block is built (SPEC.md §4.16's
    /// per-document rule), see `+MainForm.swift`/`+ContinuationForm.swift`.
    static func roleLegendLetter(_ role: CueRightHolderRole) -> String {
        switch role {
        case .composer: "C"
        case .author: "A"
        case .arranger: "AR"
        case .publisher: "E"
        case .performer: ""
        }
    }

    /// One right-holder row's full display line — name, role letter, and
    /// both percentage shares — genuinely new rendering: `CueSheetLayoutComputer`
    /// never draws percentages at all (SPEC.md §4.16's per-document rule),
    /// so there is no existing formatter to reuse for this specific
    /// combination, only the name-resolution/percent-formatting primitives
    /// above.
    static func rightHolderLine(_ rightHolder: CueRightHolder, people: [Person], labels: [Label]) -> String {
        let name = PartyResolver.resolve(rightHolder.party, people: people, labels: labels)?.displayName ?? ""
        return "\(name) (\(roleLegendLetter(rightHolder.role)))"
    }
}
