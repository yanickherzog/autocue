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
    /// The time range `buckets` actually spans — e.g. the whole file for the
    /// coarse overview tier, or the exact fetched sub-range for the on-demand
    /// detail tier (SPEC.md §4.15's two-tier model). `WaveformView` positions
    /// each bucket by where it actually falls within the *current*
    /// `visibleRangeSeconds`, rather than assuming `buckets` already spans
    /// exactly that range — the two can legitimately disagree for a brief
    /// window while a zoom/pan's on-demand detail fetch is still debounced
    /// in flight, and drawing against the true represented range (instead of
    /// always stretching bucket index linearly across the full canvas) is
    /// what keeps the displayed shape geometrically correct throughout that
    /// window instead of visibly wrong-then-jumping once the fetch resolves.
    public let representedRangeSeconds: ClosedRange<Double>

    public init(buckets: [Bucket], representedRangeSeconds: ClosedRange<Double> = 0 ... 1) {
        self.buckets = buckets
        self.representedRangeSeconds = representedRangeSeconds
    }
}

/// One cue-boundary marker overlaid on the waveform — a plain offset, never
/// a `Timecode`. `id` is the boundary's index within the caller's own
/// ordered cue list, threaded back through `onBoundaryDragged`/merge/split
/// closures so the `ACFeatures`-layer caller knows which boundary moved,
/// per SPEC.md §4.15.
///
/// `durationSeconds` is the cue's own length — `offsetSeconds
/// ..< offsetSeconds + durationSeconds` is its full extent, used only for
/// the translucent cue-span rectangle/"CUE N" label `WaveformView` draws
/// behind the waveform, never for gesture/drag logic (that's `offsetSeconds`
/// alone, unchanged). Defaults to `0` for gesture-only tests that don't
/// render and have no real duration to give it.
public struct WaveformMarker: Identifiable, Equatable {
    public let id: Int
    public let offsetSeconds: Double
    public let durationSeconds: Double

    public init(id: Int, offsetSeconds: Double, durationSeconds: Double = 0) {
        self.id = id
        self.offsetSeconds = offsetSeconds
        self.durationSeconds = durationSeconds
    }
}

/// Identifies which edge of which `WaveformMarker` a boundary gesture
/// targets — `cueIndex` is the same "index into the caller's ordered cue
/// list" identifier `WaveformMarker.id` already uses, never a `Cue.ID`
/// (`CLAUDE.md`'s Design System rule: no domain type crosses into
/// `ACDesignSystem`). SPEC.md §4.19's "Boundary markers: contiguous vs.
/// non-contiguous": every cue with a `startTimecode` has a start edge (at
/// `offsetSeconds`) and an end edge (at `offsetSeconds + durationSeconds`),
/// both independently hit-testable and draggable.
public enum WaveformBoundaryMarker: Hashable {
    case start(cueIndex: Int)
    case end(cueIndex: Int)
}
