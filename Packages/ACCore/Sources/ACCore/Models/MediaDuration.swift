import Foundation

/// A **length** of media time — "how long," never "where." Contrast with
/// `Timecode`, a *position* within an `AudioAsset`.
///
/// Named `MediaDuration` rather than `Duration` specifically to avoid colliding
/// with Swift Concurrency's own `Swift.Duration`, implicitly in scope in
/// virtually any file that touches `async`/`await` timing (SPEC.md §4.8).
public struct MediaDuration: Equatable, Comparable, Hashable, AdditiveArithmetic, Sendable {
    public let seconds: Double

    public init(seconds: Double) {
        precondition(seconds >= 0, "MediaDuration.seconds must be non-negative")
        self.seconds = seconds
    }

    public static let zero = MediaDuration(seconds: 0)

    public static func < (lhs: MediaDuration, rhs: MediaDuration) -> Bool {
        lhs.seconds < rhs.seconds
    }

    public static func + (lhs: MediaDuration, rhs: MediaDuration) -> MediaDuration {
        MediaDuration(seconds: lhs.seconds + rhs.seconds)
    }

    public static func - (lhs: MediaDuration, rhs: MediaDuration) -> MediaDuration {
        MediaDuration(seconds: lhs.seconds - rhs.seconds)
    }
}

public extension MediaDuration {
    /// `HH:MM:SS`, zero-padded, no frames — durations are declared to SUISA as
    /// a rights-accounting total, not located frame-accurately within the
    /// production; frame precision belongs to `Timecode`, not here (SPEC.md §4.8).
    var formatted: String {
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}
