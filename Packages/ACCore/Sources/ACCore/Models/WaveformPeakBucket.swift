import Foundation

/// One time bucket's min/max normalized amplitude, as stored by
/// `WaveformPeaks` (SPEC.md §4.15). Min/max-per-bucket, not average/RMS,
/// specifically to preserve visible transients a waveform display shouldn't
/// smooth away.
///
/// No `id` field — a bucket has no identity independent of its position in
/// `WaveformPeaks.buckets` (`CLAUDE.md`, "Domain Model Value-Type
/// Conformances").
public struct WaveformPeakBucket: Equatable, Hashable, Sendable {
    public let min: Float
    public let max: Float

    public init(min: Float, max: Float) {
        self.min = min
        self.max = max
    }
}
