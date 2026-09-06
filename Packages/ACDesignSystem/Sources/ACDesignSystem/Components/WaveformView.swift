import SwiftUI

/// Renders `WaveformDisplayData` — display mode only unless `markers` is
/// non-empty, in which case interactive mode (drag-to-reposition, pan,
/// zoom, split, merge, click-to-play) is also live, per SPEC.md §4.15/
/// §4.19/§4.20. Never takes an `ACCore` type — `WaveformDisplayData`/
/// `WaveformMarker` are the domain-free, design-system-local adapters an
/// `ACFeatures`-layer mapper produces at the point a screen renders this
/// (`CLAUDE.md`'s Design System rule).
///
/// **`displayData.buckets` always spans exactly `visibleRangeSeconds`** —
/// the coarse full-file overview when unzoomed, or the on-demand detail
/// tier for just the visible sub-range once zoomed (SPEC.md §4.15's
/// two-tier model); this component draws bucket index linearly across its
/// own width either way and never needs to know which tier it's looking at.
///
/// **Vertical (amplitude) zoom is owned entirely here, ephemeral,
/// never persisted** — `verticalScale` resets to `1.0` every time this view
/// is reopened, per SPEC.md §4.15's explicit, confirmed decision.
public struct WaveformView: View {
    private let displayData: WaveformDisplayData
    private let markers: [WaveformMarker]
    private let fileDurationSeconds: Double
    private let playheadOffsetSeconds: Double?
    private let onBoundaryDragged: (Int, Double) -> Void
    private let onMergeRequested: (Int) -> Void
    private let onSplitRequested: (Double) -> Void
    private let onPlayFromPoint: (Double) -> Void
    private let onPlayMarkerSpan: (Int) -> Void
    /// Fired whenever the visible range changes (pan or zoom) *or* the
    /// view's own pixel width changes — always carrying both together, so
    /// the caller can compute an on-demand-detail resolution "driven by the
    /// view's actual pixel width, not a fixed constant" (SPEC.md §4.15)
    /// without a second, separately-plumbed width channel.
    private let onVisibleRangeChanged: (ClosedRange<Double>, Double) -> Void

    @Binding private var visibleRangeSeconds: ClosedRange<Double>
    @State private var liveDragPreview: LiveDragPreview?
    @State private var verticalScale: Double = 1.0
    @State private var lastKnownWidth: CGFloat = 100

    private struct LiveDragPreview: Equatable {
        let markerID: Int
        let offsetSeconds: Double
    }

    public init(
        displayData: WaveformDisplayData,
        markers: [WaveformMarker] = [],
        visibleRangeSeconds: Binding<ClosedRange<Double>>,
        fileDurationSeconds: Double,
        playheadOffsetSeconds: Double? = nil,
        onBoundaryDragged: @escaping (Int, Double) -> Void = { _, _ in },
        onMergeRequested: @escaping (Int) -> Void = { _ in },
        onSplitRequested: @escaping (Double) -> Void = { _ in },
        onPlayFromPoint: @escaping (Double) -> Void = { _ in },
        onPlayMarkerSpan: @escaping (Int) -> Void = { _ in },
        onVisibleRangeChanged: @escaping (ClosedRange<Double>, Double) -> Void = { _, _ in }
    ) {
        self.displayData = displayData
        self.markers = markers
        _visibleRangeSeconds = visibleRangeSeconds
        self.fileDurationSeconds = fileDurationSeconds
        self.playheadOffsetSeconds = playheadOffsetSeconds
        self.onBoundaryDragged = onBoundaryDragged
        self.onMergeRequested = onMergeRequested
        self.onSplitRequested = onSplitRequested
        self.onPlayFromPoint = onPlayFromPoint
        self.onPlayMarkerSpan = onPlayMarkerSpan
        self.onVisibleRangeChanged = onVisibleRangeChanged
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    draw(context: context, size: size)
                }
                if !markers.isEmpty {
                    WaveformInteractionRepresentable(
                        visibleRangeSeconds: visibleRangeSeconds,
                        fileDurationSeconds: fileDurationSeconds,
                        markers: markers,
                        onBoundaryDragging: { markerID, seconds in
                            liveDragPreview = LiveDragPreview(markerID: markerID, offsetSeconds: seconds)
                        },
                        onBoundaryDragged: { markerID, seconds in
                            // `liveDragPreview` deliberately stays active
                            // here — clearing it synchronously on release
                            // used to cause a visible snap-back-then-jump
                            // glitch, since the marker would briefly fall
                            // back to reading its pre-drag position from
                            // `markers` before the async persist + live-
                            // stream round trip caught up. It's cleared
                            // below, in `onChange(of: markers)`, only once
                            // `markers` actually reflects the dropped
                            // position — closing that gap instead of
                            // exposing it.
                            onBoundaryDragged(markerID, seconds)
                        },
                        onMergeRequested: { markerID in
                            liveDragPreview = nil
                            onMergeRequested(markerID)
                        },
                        onSplitRequested: onSplitRequested,
                        onPanChanged: { updateVisibleRange($0, width: geometry.size.width) },
                        onZoomChanged: { updateVisibleRange($0, width: geometry.size.width) },
                        onPlayFromPoint: onPlayFromPoint,
                        onPlayMarkerSpan: onPlayMarkerSpan
                    )
                }
            }
            .overlay(alignment: .topTrailing) { zoomControls }
            .overlay(alignment: .bottomTrailing) { verticalScaleControl }
            .clipped()
            .background(Theme.Surface.reversed.background)
            .accessibilityElement()
            .accessibilityLabel(Text("Waveform"))
            .frame(minHeight: 1) // keeps geometry.size well-defined in previews
            .onAppear {
                clampVisibleRange(toFit: geometry.size)
                lastKnownWidth = geometry.size.width
                onVisibleRangeChanged(visibleRangeSeconds, geometry.size.width)
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                lastKnownWidth = newWidth
                onVisibleRangeChanged(visibleRangeSeconds, newWidth)
            }
            .onChange(of: markers) { _, newMarkers in
                guard let liveDragPreview else { return }
                guard let updated = newMarkers.first(where: { $0.id == liveDragPreview.markerID }) else {
                    // The dragged marker's cue no longer exists (e.g. an
                    // unrelated concurrent edit removed it) — nothing left
                    // to reconcile the preview against.
                    self.liveDragPreview = nil
                    return
                }
                if abs(updated.offsetSeconds - liveDragPreview.offsetSeconds) < 0.0005 {
                    self.liveDragPreview = nil
                }
            }
        }
    }

    private func updateVisibleRange(_ newRange: ClosedRange<Double>, width: CGFloat) {
        visibleRangeSeconds = newRange
        onVisibleRangeChanged(newRange, width)
    }

    private var zoomControls: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button {
                zoom(by: 1 / 1.5)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            Button {
                zoom(by: 1.5)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
        }
        .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .reversed))
        .padding(Theme.Spacing.xs)
    }

    private var verticalScaleControl: some View {
        Slider(value: $verticalScale, in: 0.25 ... 4)
            .frame(width: 100)
            .tint(Theme.Colors.accent)
            .padding(Theme.Spacing.xs)
    }

    private func zoom(by factor: Double) {
        let center = (visibleRangeSeconds.lowerBound + visibleRangeSeconds.upperBound) / 2
        let newRange = WaveformCoordinateMapper.zooming(
            visibleRangeSeconds,
            by: factor,
            aroundSeconds: center,
            fileDurationSeconds: fileDurationSeconds
        )
        visibleRangeSeconds = newRange
        onVisibleRangeChanged(newRange, lastKnownWidth)
    }

    private func clampVisibleRange(toFit _: CGSize) {
        guard visibleRangeSeconds.upperBound > fileDurationSeconds || visibleRangeSeconds.lowerBound < 0 else { return }
        visibleRangeSeconds = max(0, visibleRangeSeconds.lowerBound) ... min(
            fileDurationSeconds,
            visibleRangeSeconds.upperBound
        )
    }

    private func effectiveOffset(for marker: WaveformMarker) -> Double {
        if let liveDragPreview, liveDragPreview.markerID == marker.id {
            return liveDragPreview.offsetSeconds
        }
        return marker.offsetSeconds
    }

    /// How far from the top of the view each cue's "CUE N" label is drawn —
    /// a fixed pixel offset, not proportional to the view's own height: the
    /// label reads as a small annotation near the top edge regardless of
    /// how tall the waveform strip is, not something that should visually
    /// drift further down on a taller view.
    private static let cueLabelTopOffset: CGFloat = 25

    /// Cue-span rectangles, drawn *before* the waveform stroke below so
    /// they render behind it — one per cue, spanning its full extent
    /// (`offsetSeconds ..< offsetSeconds + durationSeconds`, SPEC.md
    /// §4.3's derived TC Out), automatically up to date on every redraw
    /// since it's computed directly from `markers`, the same live data the
    /// gesture layer already uses — no separate state to keep in sync.
    /// Answers the "where does a cue actually end vs. where does silence
    /// before the next one begin" ambiguity a start-only marker can't.
    private func drawCueSpans(context: GraphicsContext, size: CGSize) {
        for marker in markers {
            let startX = WaveformCoordinateMapper.pixelAtSeconds(
                marker.offsetSeconds,
                viewWidth: size.width,
                visibleRangeSeconds: visibleRangeSeconds
            )
            let endX = WaveformCoordinateMapper.pixelAtSeconds(
                marker.offsetSeconds + marker.durationSeconds,
                viewWidth: size.width,
                visibleRangeSeconds: visibleRangeSeconds
            )
            guard endX > 0, startX < size.width else { continue } // fully off-screen either side
            let clampedStart = max(0, startX)
            let clampedEnd = min(size.width, endX)
            guard clampedEnd > clampedStart else { continue }

            let rect = CGRect(x: clampedStart, y: 0, width: clampedEnd - clampedStart, height: size.height)
            context.fill(Path(rect), with: .color(Theme.Colors.white.opacity(0.15)))

            // 1-indexed, in left-to-right (`markers`' own, already-sorted-
            // by-start) order — `marker.id` is the cue's index in that same
            // order, so `id + 1` is exactly that position, no separate
            // numbering scheme to maintain.
            let label = Text("CUE \(marker.id + 1)")
                .font(Theme.Typography.font(.medium, size: 11))
                .foregroundColor(Theme.Colors.carbonBlack)
            context.draw(label, at: CGPoint(x: (clampedStart + clampedEnd) / 2, y: Self.cueLabelTopOffset))
        }
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let bucketCount = displayData.buckets.count
        guard bucketCount > 0, size.width > 0 else { return }
        let midY = size.height / 2
        let representedRange = displayData.representedRangeSeconds
        let representedSpan = representedRange.upperBound - representedRange.lowerBound

        drawCueSpans(context: context, size: size)

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

        for marker in markers {
            let markerPixelX = WaveformCoordinateMapper.pixelAtSeconds(
                effectiveOffset(for: marker),
                viewWidth: size.width,
                visibleRangeSeconds: visibleRangeSeconds
            )
            guard markerPixelX >= 0, markerPixelX <= size.width else { continue }
            var markerPath = Path()
            markerPath.move(to: CGPoint(x: markerPixelX, y: 0))
            markerPath.addLine(to: CGPoint(x: markerPixelX, y: size.height))
            context.stroke(markerPath, with: .color(Theme.Surface.reversed.foreground), lineWidth: 2)
        }

        if let playheadOffsetSeconds {
            let playheadPixelX = WaveformCoordinateMapper.pixelAtSeconds(
                playheadOffsetSeconds,
                viewWidth: size.width,
                visibleRangeSeconds: visibleRangeSeconds
            )
            if playheadPixelX >= 0, playheadPixelX <= size.width {
                var playheadPath = Path()
                playheadPath.move(to: CGPoint(x: playheadPixelX, y: 0))
                playheadPath.addLine(to: CGPoint(x: playheadPixelX, y: size.height))
                context.stroke(playheadPath, with: .color(Theme.Colors.accent), lineWidth: 1.5)
            }
        }
    }
}

private func previewBuckets() -> [WaveformDisplayData.Bucket] {
    (0 ..< 200).map { bucketIndex in
        let amplitude = Float(sin(Double(bucketIndex) / 5)) * 0.8
        return WaveformDisplayData.Bucket(min: -abs(amplitude), max: abs(amplitude))
    }
}

#Preview("WaveformView — display only") {
    WaveformView(
        displayData: WaveformDisplayData(buckets: previewBuckets(), representedRangeSeconds: 0 ... 60),
        visibleRangeSeconds: .constant(0 ... 60),
        fileDurationSeconds: 60
    )
    .frame(height: 120)
    .padding()
}

#Preview("WaveformView — interactive, with markers") {
    WaveformView(
        displayData: WaveformDisplayData(buckets: previewBuckets(), representedRangeSeconds: 0 ... 60),
        markers: [
            WaveformMarker(id: 0, offsetSeconds: 10, durationSeconds: 20),
            WaveformMarker(id: 1, offsetSeconds: 40, durationSeconds: 15),
        ],
        visibleRangeSeconds: .constant(0 ... 60),
        fileDurationSeconds: 60,
        playheadOffsetSeconds: 25
    )
    .frame(height: 120)
    .padding()
}
