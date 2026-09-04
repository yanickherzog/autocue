import Foundation

/// The design-system-local, domain-free adapter `WaveformView` actually
/// consumes — never `ACCore`'s `WaveformPeaks`/`WaveformPeakBucket` directly
/// (`CLAUDE.md`'s Design System rule; SPEC.md §4.15). An `ACFeatures`-layer
/// mapper converts the real domain type into this at the point a screen
/// renders it, the same adapter-at-the-edge pattern `CueTableView`'s row
/// protocol already establishes.
public struct WaveformDisplayData: Equatable {
    public struct Bucket: Equatable {
        /// Normalized amplitude, `-1.0...1.0`.
        public let min: Float
        public let max: Float

        public init(min: Float, max: Float) {
            self.min = min
            self.max = max
        }
    }

    public let buckets: [Bucket]

    public init(buckets: [Bucket]) {
        self.buckets = buckets
    }
}

/// One cue-boundary marker overlaid on the waveform — a plain offset, never
/// a `Timecode`. `id` is the boundary's index within the caller's own
/// ordered cue list, threaded back through `onBoundaryDragged`/merge/split
/// closures so the `ACFeatures`-layer caller knows which boundary moved,
/// per SPEC.md §4.15.
public struct WaveformMarker: Identifiable, Equatable {
    public let id: Int
    public let offsetSeconds: Double

    public init(id: Int, offsetSeconds: Double) {
        self.id = id
        self.offsetSeconds = offsetSeconds
    }
}
