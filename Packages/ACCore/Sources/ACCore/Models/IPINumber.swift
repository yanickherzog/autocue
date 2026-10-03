import Foundation

/// Real-structure validation and display formatting for a CISAC IPI Name
/// Number — `Person.ipiNumber`'s own real-world format (SPEC.md §4.5).
///
/// **Real structure, confirmed against CISAC/industry sources and
/// hand-verified against five independently-sourced real example numbers —
/// not guessed:** 11 digits total. **The first 9 digits ARE the base
/// number** (including any leading zeros — those are genuine, significant
/// positions of the zero-padded base, not a separate prefix layered on top
/// of a shorter value); **the last 2 are check digits** computed from the
/// first 9 via a real algorithm (see `isValid` below). There is no 2-digit
/// padding/prefix distinct from the base — confirmed against CISAC's own
/// technical basis (ISO/TC 46/SC 9 N 268) and cross-checked against three
/// real, publicly-documented IPI Name Numbers (Prince's own three IPI
/// numbers, listed on Wikipedia's "Interested Parties Information" article:
/// `00045620792`, `00052210040`, `00334284961`), all three of which pass
/// `isValid` below, plus two earlier hand-picked examples
/// (`01234567846`, `00123456790`). **This structural fact governs `isValid`
/// only — it has no bearing on how the number is displayed; see
/// `grouped(_:)` below.**
///
/// **`grouped(_:)` — fixed 2026-10-03, twice the same day.** The first fix
/// replaced an original, confirmed-wrong `3-2-2-2`-of-the-trailing-9
/// convention (which dropped 2 real digits) with a `3-3-3`-base
/// `+`-hyphenated-check-digits format — reasoned from `isValid`'s own
/// structure, since no real display example was available at the time to
/// check against. **That second format was also wrong, corrected the same
/// day by real evidence, not a style preference:** the project owner
/// directly read their own real, previously-submitted, SUISA-accepted cue
/// sheet, which displays their actual IPI number as `"IPI Nr. 00386 75 75
/// 00"` — all 11 real digits, grouped `5-2-2-2`, no digits dropped, **no
/// hyphen, and no visual split between base and check digits at all.** The
/// real SUISA-accepted display simply groups the full, unmodified 11-digit
/// number for legibility — it draws no distinction between "base" and
/// "check" digits on the page, even though `isValid`'s internal algorithm
/// (above) does treat them differently for validation purposes. Confirmed
/// directly: `00386757500` (the real IPI number behind that real document)
/// grouped `5-2-2-2` is exactly `"00386 75 75 00"` — matching the real
/// document character-for-character — and the earlier placeholder's own
/// originally-expected `"00123 45 67 89"` is exactly what `5-2-2-2` of
/// `00123456789` produces too. See `docs/DECISIONS.md`, 2026-10-03, for the
/// full record of both corrections and every downstream PDF either one
/// affected.
///
/// Used by two real, independent call sites: the cue sheet PDF export
/// (`ACExport`, display only) and the Composer Profile feature's own
/// save-confirmation step (`ACFeatures`) — promoted here, to `ACCore`,
/// specifically because a second real consumer exists (`CLAUDE.md` rule 7);
/// neither layer duplicates this logic independently.
public enum IPINumber {
    /// `true` iff `raw` is exactly 11 digits (after stripping any
    /// non-digit formatting characters a user might have typed, e.g.
    /// spaces) and its last 2 digits are the correct check digits for its
    /// first 9, per the real CISAC algorithm: each of the first 9 digits is
    /// multiplied by a descending weight (10 down to 2), the products
    /// summed, reduced mod 101, and — if that reduction is non-zero —
    /// subtracted from 101 (mod 100) to get the expected 2-digit check
    /// value. Purely internal to validation — see this type's own doc
    /// comment for why this 9+2 structure has no bearing on `grouped(_:)`'s
    /// displayed output.
    public static func isValid(_ raw: String) -> Bool {
        let digits = raw.filter(\.isNumber)
        guard digits.count == 11 else { return false }
        let base = Array(digits.prefix(9))
        let checkDigits = String(digits.suffix(2))

        let weights = [10, 9, 8, 7, 6, 5, 4, 3, 2]
        let sum = zip(base, weights).reduce(0) { partial, pair in
            let (digitCharacter, weight) = pair
            return partial + (digitCharacter.wholeNumberValue ?? 0) * weight
        }
        var expected = sum % 101
        if expected != 0 {
            expected = (101 - expected) % 100
        }
        return String(format: "%02d", expected) == checkDigits
    }

    /// Displays every real digit — never drops, fabricates, or splits any —
    /// grouped `5-2-2-2` from the left: the full, unmodified number as-is,
    /// just space-separated for legibility (`"00123456789"` →
    /// `"00123 45 67 89"`). Confirmed against a real, SUISA-accepted
    /// document (`"00386757500"` → `"00386 75 75 00"`, this type's own doc
    /// comment) — not derived from `isValid`'s internal base/check
    /// structure, which this display deliberately does not reflect (no
    /// hyphen, no visual distinction between the two). For anything shorter
    /// than 5 digits, the whole string is one ungrouped block; longer
    /// inputs continue grouping by 2 past the first 5, regardless of
    /// overall length. Non-numeric input is returned unchanged — this is a
    /// display helper, never a validation gate.
    public static func grouped(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return raw }

        var groups: [String] = []
        var remaining = Substring(digits)
        let firstCount = min(5, remaining.count)
        groups.append(String(remaining.prefix(firstCount)))
        remaining = remaining.dropFirst(firstCount)
        while !remaining.isEmpty {
            let count = min(2, remaining.count)
            groups.append(String(remaining.prefix(count)))
            remaining = remaining.dropFirst(count)
        }
        return groups.joined(separator: " ")
    }
}
