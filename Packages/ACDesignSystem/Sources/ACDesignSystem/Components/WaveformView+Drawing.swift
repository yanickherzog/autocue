import SwiftUI

/// Split out of `WaveformView.swift` purely to stay under this project's
/// file-length lint limit — these are `Canvas`-drawing helpers for
/// `draw(context:size:)`, which stays in the primary file's type body
/// alongside `body` itself. All properties/methods referenced here that live
/// in the primary file (`markers`, `visibleRangeSeconds`, `verticalScale`,
/// `grabbedMarker`, `liveDragPreviews`, `playheadOffsetSeconds`,
/// `effectiveStartOffset`/`effectiveEndOffset`) are `internal`, not
/// `private`, specifically so this extension can see them.
extension WaveformView {
    /// How far from the top of the view each cue's "CUE N" label is drawn —
    /// a fixed pixel offset, not proportional to the view's own height: the
    /// label reads as a small annotation near the top edge regardless of
    /// how tall the waveform strip is, not something that should visually
    /// drift further down on a taller view.
    private static let cueLabelTopOffset: CGFloat = 25

    /// Cue-span rectangles, drawn *after* the waveform stroke
    /// (`draw(context:size:)`, `WaveformView.swift`) so they always render
    /// on top of it — one per cue, spanning its full extent
    /// (`offsetSeconds ..< offsetSeconds + durationSeconds`, SPEC.md §4.3's
    /// derived TC Out), automatically up to date on every redraw since it's
    /// computed directly from `markers`, the same live data the gesture
    /// layer already uses — no separate state to keep in sync. Answers the
    /// "where does a cue actually end vs. where does silence before the next
    /// one begin" ambiguity a start-only marker can't. The fill stays
    /// translucent specifically so the waveform trace remains visible
    /// underneath it — drawing on top only fixes legibility at high vertical
    /// zoom, where the trace's peaks used to reach past a dimmer,
    /// earlier-drawn span/label and obscure both.
    func drawCueSpans(context: GraphicsContext, size: CGSize) {
        for marker in markers {
            let startX = WaveformCoordinateMapper.pixelAtSeconds(
                effectiveStartOffset(for: marker),
                viewWidth: size.width,
                visibleRangeSeconds: visibleRangeSeconds
            )
            let endX = WaveformCoordinateMapper.pixelAtSeconds(
                effectiveEndOffset(for: marker),
                viewWidth: size.width,
                visibleRangeSeconds: visibleRangeSeconds
            )
            guard endX > 0, startX < size.width else { continue } // fully off-screen either side
            let clampedStart = max(0, startX)
            let clampedEnd = min(size.width, endX)
            guard clampedEnd > clampedStart else { continue }

            let rect = CGRect(x: clampedStart, y: 0, width: clampedEnd - clampedStart, height: size.height)
            context.fill(Path(rect), with: .color(fillColor(for: marker)))

            // 1-indexed, in left-to-right (`markers`' own, already-sorted-
            // by-start) order — `marker.id` is the cue's index in that same
            // order, so `id + 1` is exactly that position, no separate
            // numbering scheme to maintain.
            let label = Text("CUE \(marker.id + 1)")
                .font(Theme.Typography.font(.medium, size: 11))
                .foregroundColor(Theme.Colors.white)
            context.draw(label, at: CGPoint(x: (clampedStart + clampedEnd) / 2, y: Self.cueLabelTopOffset))
        }
    }

    /// Whichever cue's span is currently being actively edited — grabbing a
    /// marker at a coincident (zero-gap) position resolves to one specific
    /// cue via an otherwise-invisible tie-break (SPEC.md §4.19), which reads
    /// as "nothing happened" without this: the instant a marker is grabbed,
    /// before any drag motion even occurs, the cue it actually belongs to is
    /// highlighted so which one responded is immediately unambiguous.
    /// Checks both `grabbedMarker` (set at `mouseDown`, covers a plain
    /// click-and-hold with no movement yet) and `liveDragPreviews` (set once
    /// real movement starts, and the only place a contiguous push-through's
    /// *second*, carried-along cue ever shows up) — together they cover the
    /// whole gesture with no gap between "grabbed" and "now dragging."
    /// Reuses `Theme.Colors.accent` (Burgundy), the same "this is
    /// active/interactive" role it already plays for the waveform trace,
    /// playhead, and zoom slider.
    private func fillColor(for marker: WaveformMarker) -> Color {
        let isActive = grabbedMarker == .start(cueIndex: marker.id)
            || grabbedMarker == .end(cueIndex: marker.id)
            || liveDragPreviews[.start(cueIndex: marker.id)] != nil
            || liveDragPreviews[.end(cueIndex: marker.id)] != nil
        return isActive ? Theme.Colors.accent.opacity(0.35) : Theme.Colors.white.opacity(0.15)
    }

    func drawWaveform(context: GraphicsContext, size: CGSize) {
        let bucketCount = displayData.buckets.count
        let midY = size.height / 2
        let representedRange = displayData.representedRangeSeconds
        let representedSpan = representedRange.upperBound - representedRange.lowerBound

        var wavePath = Path()
        for (bucketIndex, bucket) in displayData.buckets.enumerated() {
            // Positioned by the time `bucketIndex` actually represents,
            // mapped through the *current* `visibleRangeSeconds` — not a
            // blind linear stretch across the canvas — so a still-coarser
            // or still-stale `displayData` (e.g. while a zoom's on-demand
            // detail fetch is debounced) still renders at the geometrically
            // correct position/width for the current zoom level.
            let bucketTimeSeconds = representedSpan > 0
                ? representedRange.lowerBound + (Double(bucketIndex) / Double(bucketCount)) * representedSpan
                : representedRange.lowerBound
            let xPosition = WaveformCoordinateMapper.pixelAtSeconds(
                bucketTimeSeconds,
                viewWidth: size.width,
                visibleRangeSeconds: visibleRangeSeconds
            )
            guard xPosition >= 0, xPosition <= size.width else { continue }
            let topY = midY - CGFloat(bucket.max) * midY * CGFloat(verticalScale)
            let bottomY = midY - CGFloat(bucket.min) * midY * CGFloat(verticalScale)
            wavePath.move(to: CGPoint(x: xPosition, y: topY))
            wavePath.addLine(to: CGPoint(x: xPosition, y: bottomY))
        }
        context.stroke(wavePath, with: .color(Theme.Colors.accent), lineWidth: 1)
    }

    /// Matches `strokeMarkerLine`'s own `lineWidth` below — kept as one
    /// named constant so the inset half-width can never silently drift out
    /// of sync with the stroke it's insetting for.
    private static let markerStrokeWidth: CGFloat = 2

    /// A marker sitting exactly at the file's absolute start or end has its
    /// pixel position exactly on the canvas's own `.clipped()` boundary —
    /// with no inset, roughly half the stroke's width would render outside
    /// that boundary and get clipped away, leaving only a faint, partial
    /// sliver instead of a full, clearly-visible line (found via manual
    /// testing, not a color collision — every marker already uses the same
    /// `Theme.Surface.reversed.foreground` stroke everywhere else). Clamping
    /// the *drawn* position 1pt inside each edge keeps the full stroke
    /// width always inside the clip region; this is purely cosmetic; hit
    /// radius (8pt) makes the 1pt shift imperceptible to the gesture layer,
    /// which computes hit-testing from the unmodified seconds value.
    private func strokeMarkerLine(atSeconds seconds: Double, context: GraphicsContext, size: CGSize) {
        let pixelX = WaveformCoordinateMapper.pixelAtSeconds(
            seconds,
            viewWidth: size.width,
            visibleRangeSeconds: visibleRangeSeconds
        )
        guard pixelX >= 0, pixelX <= size.width else { return }
        let halfStrokeWidth = Self.markerStrokeWidth / 2
        let renderX = min(max(pixelX, halfStrokeWidth), size.width - halfStrokeWidth)
        var markerPath = Path()
        markerPath.move(to: CGPoint(x: renderX, y: 0))
        markerPath.addLine(to: CGPoint(x: renderX, y: size.height))
        context.stroke(markerPath, with: .color(Theme.Surface.reversed.foreground), lineWidth: Self.markerStrokeWidth)
    }

    /// Every cue with a start contributes a start edge and an end edge
    /// (SPEC.md §4.19) — both drawn, except an end edge coincident with the
    /// next cue's start edge (a contiguous boundary), which is skipped here
    /// to avoid a doubled/overlapping stroke; that shared position is still
    /// drawn once, by the next marker's own start edge.
    func drawMarkerLines(context: GraphicsContext, size: CGSize) {
        for marker in markers {
            strokeMarkerLine(atSeconds: effectiveStartOffset(for: marker), context: context, size: size)

            let endSeconds = effectiveEndOffset(for: marker)
            let nextStartSeconds = markers.first { $0.id == marker.id + 1 }.map(effectiveStartOffset(for:))
            if let nextStartSeconds, abs(endSeconds - nextStartSeconds) <= 0.001 {
                continue // coincident with the next marker's start — already drawn by it
            }
            strokeMarkerLine(atSeconds: endSeconds, context: context, size: size)
        }
    }

    func drawPlayhead(context: GraphicsContext, size: CGSize) {
        guard let playheadOffsetSeconds else { return }
        let playheadPixelX = WaveformCoordinateMapper.pixelAtSeconds(
            playheadOffsetSeconds,
            viewWidth: size.width,
            visibleRangeSeconds: visibleRangeSeconds
        )
        guard playheadPixelX >= 0, playheadPixelX <= size.width else { return }
        var playheadPath = Path()
        playheadPath.move(to: CGPoint(x: playheadPixelX, y: 0))
        playheadPath.addLine(to: CGPoint(x: playheadPixelX, y: size.height))
        context.stroke(playheadPath, with: .color(Theme.Colors.accent), lineWidth: 1.5)
    }
}
