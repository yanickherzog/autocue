import Foundation

/// Light, non-blocking shape check and display formatting for an
/// International Standard Recording Code — `Cue.recordingISRC`'s own
/// real-world format (SPEC.md §4.3).
///
/// **Real structure:** 12 characters — 2-letter country code, 3-character
/// alphanumeric registrant code, 2-digit year of reference, 5-digit
/// designation code (`CC-XXX-YY-NNNNN`). Hyphens are a display convention
/// only, never part of the real 12-character identifier — the same
/// "formatting characters stripped before checking" approach `IPINumber`
/// already establishes for a different PRO identifier.
///
/// **Deliberately no check-digit algorithm, unlike `IPINumber`.** ISRC has
/// no real check-digit scheme to verify against — it's an assigned
/// identifier, not a computed one. `isValid` therefore checks shape only
/// (length, and country/registrant/year/designation each being the right
/// kind of character), not a cryptographic guarantee the code itself is
/// genuine. This is intentionally weaker than `IPINumber.isValid` — the
/// goal here is catching an obvious typo before it reaches a submitted
/// document (the same motivation a fabricated IPI number's own bug fix
/// established, `docs/DECISIONS.md`), not full validation.
public enum ISRCNumber {
    /// `true` iff `raw`, with any non-alphanumeric formatting characters
    /// stripped, is exactly 12 characters shaped `CCXXXYYNNNNN`: 2 letters,
    /// 3 alphanumeric, 2 digits, 5 digits.
    public static func isValid(_ raw: String) -> Bool {
        let characters = Array(raw.filter { $0.isLetter || $0.isNumber })
        guard characters.count == 12 else { return false }

        let countryCode = characters[0 ... 1]
        let yearDigits = characters[5 ... 6]
        let designationDigits = characters[7 ... 11]

        guard countryCode.allSatisfy(\.isLetter) else { return false }
        guard yearDigits.allSatisfy(\.isNumber) else { return false }
        guard designationDigits.allSatisfy(\.isNumber) else { return false }
        return true
    }

    /// Normalizes to the standard hyphenated display form —
    /// `CC-XXX-YY-NNNNN`, uppercased — from any input shape (hyphens
    /// present or not, mixed case). Non-conforming input (not exactly 12
    /// alphanumeric characters once stripped) is returned unchanged,
    /// uppercased only — this is a display helper, never a validation
    /// gate, the same deliberate split `IPINumber.grouped(_:)` already
    /// establishes.
    public static func normalized(_ raw: String) -> String {
        let characters = raw.filter { $0.isLetter || $0.isNumber }
        guard characters.count == 12 else { return raw.uppercased() }
        let upper = characters.uppercased()
        let parts = [
            upper.prefix(2),
            upper.dropFirst(2).prefix(3),
            upper.dropFirst(5).prefix(2),
            upper.dropFirst(7).prefix(5),
        ]
        return parts.joined(separator: "-")
    }
}
