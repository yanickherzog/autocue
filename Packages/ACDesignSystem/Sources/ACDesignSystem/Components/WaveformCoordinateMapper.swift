import Foundation

/// Pixel-to-time (and inverse) math for `WaveformView`'s interactive mode —
/// a plain, pure, `Double`/`ClosedRange<Double>` function set, independent
/// of `WaveformView`/`WaveformInteractionView` themselves so it's directly
/// unit-testable (`ROADMAP.md` D9/T9.3's own Testing Requirements: "the
/// boundary-marker offset-mapping math... is unit-tested as a pure function,
/// independent of `WaveformView` itself"). One implementation, used for
/// every zoomed-coordinate-space computation this component needs —
/// boundary-marker drag, split-offset, click-to-play, and pan-translation
/// math all go through this, not four independently-reinvented copies.
public enum WaveformCoordinateMapper {
    /// Converts a pixel x-offset within a `viewWidth`-wide strip to a
    /// seconds offset, against the currently-visible time window —
    /// correctly zoomed-aware: computed against `visibleRangeSeconds`, never
    /// the full file range, whenever zoomed in (SPEC.md §4.15).
    public static func secondsAtPixel(
        _ pixelX: Double,
        viewWidth: Double,
        visibleRangeSeconds: ClosedRange<Double>
    ) -> Double {
        guard viewWidth > 0 else { return visibleRangeSeconds.lowerBound }
        let fraction = pixelX / viewWidth
        let span = visibleRangeSeconds.upperBound - visibleRangeSeconds.lowerBound
        return visibleRangeSeconds.lowerBound + fraction * span
    }

    /// The inverse of `secondsAtPixel` — where a given seconds offset falls
    /// within the strip, for drawing markers/the playhead at the correct
    /// on-screen position.
    public static func pixelAtSeconds(
        _ seconds: Double,
        viewWidth: Double,
        visibleRangeSeconds: ClosedRange<Double>
    ) -> Double {
        let span = visibleRangeSeconds.upperBound - visibleRangeSeconds.lowerBound
        guard span > 0 else { return 0 }
        let fraction = (seconds - visibleRangeSeconds.lowerBound) / span
        return fraction * viewWidth
    }

    /// Shifts `visibleRangeSeconds` by `delta` seconds at constant width,
    /// clamped so it can never extend past `[0, fileDurationSeconds]`
    /// (SPEC.md §4.15's pan-clamping rule).
    public static func panning(
        _ visibleRangeSeconds: ClosedRange<Double>,
        byDeltaSeconds delta: Double,
        fileDurationSeconds: Double
    ) -> ClosedRange<Double> {
        let width = visibleRangeSeconds.upperBound - visibleRangeSeconds.lowerBound
        let clampedWidth = min(width, max(0, fileDurationSeconds))
        let newLower = max(0, min(visibleRangeSeconds.lowerBound + delta, fileDurationSeconds - clampedWidth))
        return newLower ... (newLower + clampedWidth)
    }

    /// Narrows/widens `visibleRangeSeconds` by `factor` (`> 1` zooms in,
    /// `< 1` zooms out) around `centerSeconds`, clamped to
    /// `[0, fileDurationSeconds]` and never narrower than
    /// `minimumWidthSeconds`.
    public static func zooming(
        _ visibleRangeSeconds: ClosedRange<Double>,
        by factor: Double,
        aroundSeconds centerSeconds: Double,
        fileDurationSeconds: Double,
        minimumWidthSeconds: Double = 0.1
    ) -> ClosedRange<Double> {
        let currentWidth = visibleRangeSeconds.upperBound - visibleRangeSeconds.lowerBound
        let newWidth = max(minimumWidthSeconds, min(fileDurationSeconds, currentWidth / max(factor, 0.0001)))
        let centerFraction = currentWidth > 0 ? (centerSeconds - visibleRangeSeconds.lowerBound) / currentWidth : 0.5
        let newLower = max(0, min(centerSeconds - centerFraction * newWidth, fileDurationSeconds - newWidth))
        return newLower ... (newLower + newWidth)
    }
}
