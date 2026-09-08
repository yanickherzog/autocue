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
    /// Not `private`: `WaveformView+Drawing.swift`'s `Canvas` drawing
    /// functions (split into their own file purely to stay under this
    /// project's file-length lint limit) need these too — still `internal`,
    /// never exposed as public API.
    let displayData: WaveformDisplayData
    let markers: [WaveformMarker]
    private let fileDurationSeconds: Double
    let playheadOffsetSeconds: Double?
    private let onBoundaryDragged: (WaveformBoundaryMarker, Double) -> Void
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

    @Binding var visibleRangeSeconds: ClosedRange<Double>
    /// Up to two entries during a contiguous push-through (SPEC.md §4.19) —
    /// the grabbed marker's own preview, and, only while actually pushing
    /// into an already-touching neighbor, that neighbor's preview too, so
    /// both spans visibly move together during the drag rather than only
    /// snapping into place once the drag commits.
    @State var liveDragPreviews: [WaveformBoundaryMarker: Double] = [:]
    /// Which marker was hit-tested at `mouseDown`, kept only for the
    /// coincident-tie-break highlight — set the instant a marker is grabbed,
    /// before any drag motion, and cleared on every `mouseUp` regardless of
    /// outcome (SPEC.md §4.19), so a plain click never leaves it stuck.
    /// Deliberately separate from `liveDragPreviews`: that only ever
    /// populates once real movement occurs, which would miss the
    /// no-movement click-and-hold case this exists to cover.
    @State var grabbedMarker: WaveformBoundaryMarker?
    @State var verticalScale: Double = 1.0

    public init(
        displayData: WaveformDisplayData,
        markers: [WaveformMarker] = [],
        visibleRangeSeconds: Binding<ClosedRange<Double>>,
        fileDurationSeconds: Double,
        playheadOffsetSeconds: Double? = nil,
        onBoundaryDragged: @escaping (WaveformBoundaryMarker, Double) -> Void = { _, _ in },
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
                        onBoundaryDragging: { marker, seconds in
                            liveDragPreviews[marker] = seconds
                        },
                        onBoundaryDragged: { marker, seconds in
                            // `liveDragPreviews` deliberately stays active
                            // here — clearing it synchronously on release
                            // used to cause a visible snap-back-then-jump
                            // glitch, since the marker would briefly fall
                            // back to reading its pre-drag position from
                            // `markers` before the async persist + live-
                            // stream round trip caught up. Each entry is
                            // cleared below, in `onChange(of: markers)`,
                            // only once `markers` actually reflects that
                            // entry's dropped position — closing that gap
                            // instead of exposing it.
                            onBoundaryDragged(marker, seconds)
                        },
                        onMarkerGrabbed: { marker in
                            grabbedMarker = marker
                        },
                        onMarkerReleased: {
                            grabbedMarker = nil
                        },
                        onMergeRequested: { markerID in
                            liveDragPreviews = [:]
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
            .overlay(alignment: .bottomTrailing) { verticalScaleControl }
            .clipped()
            .background(Theme.Surface.reversed.background)
            .accessibilityElement()
            .accessibilityLabel(Text("Waveform"))
            .frame(minHeight: 1) // keeps geometry.size well-defined in previews
            .onAppear {
                clampVisibleRange(toFit: geometry.size)
                onVisibleRangeChanged(visibleRangeSeconds, geometry.size.width)
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                onVisibleRangeChanged(visibleRangeSeconds, newWidth)
            }
            .onChange(of: markers) { _, newMarkers in
                guard !liveDragPreviews.isEmpty else { return }
                for (marker, previewOffset) in liveDragPreviews {
                    guard let realOffset = Self.realOffset(for: marker, in: newMarkers) else {
                        // The dragged marker's cue no longer exists (e.g. an
                        // unrelated concurrent edit removed it) — nothing
                        // left to reconcile this entry's preview against.
                        liveDragPreviews.removeValue(forKey: marker)
                        continue
                    }
                    if abs(realOffset - previewOffset) < 0.0005 {
                        liveDragPreviews.removeValue(forKey: marker)
                    }
                }
            }
        }
    }

    private func updateVisibleRange(_ newRange: ClosedRange<Double>, width: CGFloat) {
        visibleRangeSeconds = newRange
        onVisibleRangeChanged(newRange, width)
    }

    private var verticalScaleControl: some View {
        Slider(value: $verticalScale, in: 0.25 ... 4)
            .frame(width: 100)
            .tint(Theme.Colors.accent)
            .padding(Theme.Spacing.xs)
    }

    private func clampVisibleRange(toFit _: CGSize) {
        guard visibleRangeSeconds.upperBound > fileDurationSeconds || visibleRangeSeconds.lowerBound < 0 else { return }
        visibleRangeSeconds = max(0, visibleRangeSeconds.lowerBound) ... min(
            fileDurationSeconds,
            visibleRangeSeconds.upperBound
        )
    }

    func effectiveStartOffset(for marker: WaveformMarker) -> Double {
        liveDragPreviews[.start(cueIndex: marker.id)] ?? marker.offsetSeconds
    }

    func effectiveEndOffset(for marker: WaveformMarker) -> Double {
        liveDragPreviews[.end(cueIndex: marker.id)] ?? (marker.offsetSeconds + marker.durationSeconds)
    }

    private static func realOffset(for marker: WaveformBoundaryMarker, in markers: [WaveformMarker]) -> Double? {
        switch marker {
        case let .start(cueIndex):
            return markers.first { $0.id == cueIndex }?.offsetSeconds
        case let .end(cueIndex):
            guard let found = markers.first(where: { $0.id == cueIndex }) else { return nil }
            return found.offsetSeconds + found.durationSeconds
        }
    }

    func draw(context: GraphicsContext, size: CGSize) {
        guard displayData.buckets.count > 0, size.width > 0 else { return }
        // Waveform first, cue spans/labels on top of it — at high vertical
        // zoom the trace's peaks can reach well past the span rect's fill
        // and the "CUE N" label; drawing the overlay second keeps it
        // legible regardless of amplitude/zoom level. The span fill stays
        // translucent specifically so the trace remains visible underneath
        // it, same as before — only the draw order changed.
        drawWaveform(context: context, size: size)
        drawCueSpans(context: context, size: size)
        drawMarkerLines(context: context, size: size)
        drawPlayhead(context: context, size: size)
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
