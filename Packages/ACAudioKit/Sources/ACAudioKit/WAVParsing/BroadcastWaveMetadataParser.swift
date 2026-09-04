import ACCore
import Foundation

/// Parses a `bext` (Broadcast Wave Format) chunk payload into
/// `ACCore.BroadcastWaveMetadata` (SPEC.md §4.10). Named `...Parser`, not
/// reusing `BroadcastWaveMetadata` itself, to avoid a same-concept name
/// clash with the `ACCore` domain type of that name (`CLAUDE.md`, Naming
/// Conventions: "files named exactly after the primary type they contain") —
/// this file's primary type is the parser, not a second domain value.
///
/// The BWF `bext` chunk is a fixed 602-byte header (this parser reads only
/// the subset of fields `BroadcastWaveMetadata` actually surfaces) optionally
/// followed by a variable-length coding-history string this app doesn't
/// model.
enum BroadcastWaveMetadataParser {
    private static let descriptionRange = 0 ..< 256
    private static let originatorRange = 256 ..< 288
    private static let originatorReferenceRange = 288 ..< 320
    private static let originationDateRange = 320 ..< 330
    private static let originationTimeRange = 330 ..< 338
    private static let timeReferenceLowRange = 338 ..< 342
    private static let timeReferenceHighRange = 342 ..< 346
    private static let minimumFixedPayloadSize = 346

    /// Returns `nil` for a payload too short to be a real `bext` chunk —
    /// treated as "chunk absent," never a crash.
    static func parse(_ payload: Data) -> BroadcastWaveMetadata? {
        guard payload.count >= minimumFixedPayloadSize else { return nil }

        let description = nonEmptyASCIIString(payload, range: descriptionRange)
        let originator = nonEmptyASCIIString(payload, range: originatorRange)
        let originatorReference = nonEmptyASCIIString(payload, range: originatorReferenceRange)
        let dateString = nonEmptyASCIIString(payload, range: originationDateRange)
        let timeString = nonEmptyASCIIString(payload, range: originationTimeRange)

        let low = UInt64(payload.readUInt32LittleEndian(at: timeReferenceLowRange.lowerBound))
        let high = UInt64(payload.readUInt32LittleEndian(at: timeReferenceHighRange.lowerBound))
        let timeReferenceSamples = (high << 32) | low

        return BroadcastWaveMetadata(
            description: description,
            originator: originator,
            originatorReference: originatorReference,
            originationDate: originationDate(dateString: dateString, timeString: timeString),
            timeReferenceSamples: timeReferenceSamples == 0 ? nil : timeReferenceSamples
        )
    }

    private static func nonEmptyASCIIString(_ payload: Data, range: Range<Int>) -> String? {
        let base = payload.startIndex
        let slice = payload.subdata(in: (base + range.lowerBound) ..< (base + range.upperBound))
        let trimmed = slice.prefix { $0 != 0 }
        let string = (String(bytes: trimmed, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespaces)
        return string.isEmpty ? nil : string
    }

    /// Combines BWF's separate `OriginationDate` ("YYYY-MM-DD") and
    /// `OriginationTime` ("HH:MM:SS") fields into one `Date`, interpreted as
    /// UTC — this is display-only metadata (SPEC.md §4.10) with no
    /// round-trip requirement finer than "populated when the chunk is
    /// present," so a single fixed-timezone interpretation is sufficient.
    private static func originationDate(dateString: String?, timeString: String?) -> Date? {
        guard let dateString, let timeString else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: "\(dateString) \(timeString)")
    }
}

private extension Data {
    func readUInt32LittleEndian(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        guard base + 4 <= endIndex else { return 0 }
        return UInt32(self[base]) | (UInt32(self[base + 1]) << 8) | (UInt32(self[base + 2]) << 16) |
            (UInt32(self[base + 3]) << 24)
    }
}
