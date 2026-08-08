import Foundation

/// Metadata read from a WAV file's `bext` (Broadcast Wave) chunk, when present
/// (SPEC.md §4.10). `nil` on `AudioAsset` for a file that isn't BWF-tagged.
///
/// No `id` field: this type has no identity of its own independent of the
/// `AudioAsset` it describes — same "no `id` field, no `Identifiable`" shape
/// as `PostalAddress`/`Party` (`CLAUDE.md`, "Domain Model Value-Type
/// Conformances").
public struct BroadcastWaveMetadata: Equatable, Sendable {
    public let description: String?
    public let originator: String?
    public let originatorReference: String?
    public let originationDate: Date?
    public let timeReferenceSamples: UInt64?

    public init(
        description: String? = nil,
        originator: String? = nil,
        originatorReference: String? = nil,
        originationDate: Date? = nil,
        timeReferenceSamples: UInt64? = nil
    ) {
        self.description = description
        self.originator = originator
        self.originatorReference = originatorReference
        self.originationDate = originationDate
        self.timeReferenceSamples = timeReferenceSamples
    }
}
