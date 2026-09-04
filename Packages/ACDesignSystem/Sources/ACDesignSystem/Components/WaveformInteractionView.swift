import AppKit
import SwiftUI

/// The interaction half of `WaveformView`'s interactive mode — the full
/// seven-gesture disambiguation set from SPEC.md §4.15, implemented as a
/// plain `NSView` subclass rather than composed SwiftUI gestures.
/// `CLAUDE.md`'s Technology Stack explicitly allows AppKit interop "when
/// SwiftUI has a genuine gap" — this qualifies: SwiftUI's composed-gesture
/// system doesn't cleanly express "the same drag start point means
/// different things depending on where it landed, decided once, never
/// re-evaluated" plus modifier-key-dependent click semantics, all on one
/// surface. A raw `NSView` gets direct access to click location,
/// `NSEvent.modifierFlags` (for ⌥), and drag delta, deciding gesture
/// classification exactly once per gesture start, per §4.15's own stated
/// rule. Pure interaction/hit-testing — draws nothing itself; `WaveformView`
/// layers this transparently over its own `Canvas` rendering.
final class WaveformInteractionNSView: NSView {
    var visibleRangeSeconds: ClosedRange<Double> = 0 ... 1
    var fileDurationSeconds: Double = 1
    var markers: [WaveformMarker] = []
    var markerHitRadius: CGFloat = 8

    /// Live preview during a reposition drag — fired continuously so the
    /// host can redraw the dragged marker following the cursor without
    /// writing through to any Use Case; `onBoundaryDragged` (below) is the
    /// one, single commit point.
    var onBoundaryDragging: ((Int, Double) -> Void)?
    var onBoundaryDragged: ((Int, Double) -> Void)?
    var onMergeRequested: ((Int) -> Void)?
    var onSplitRequested: ((Double) -> Void)?
    var onPanChanged: ((ClosedRange<Double>) -> Void)?
    var onZoomChanged: ((ClosedRange<Double>) -> Void)?
    var onPlayFromPoint: ((Double) -> Void)?
    var onPlayMarkerSpan: ((Int) -> Void)?

    private enum ActiveDrag {
        case pan(startRange: ClosedRange<Double>, startLocationX: CGFloat)
        case reposition(markerID: Int)
        /// Classified once a reposition drag crosses the strip's vertical
        /// bounds — from this point on, horizontal movement is ignored and
        /// the gesture resolves to merge-or-cancel on release, never back to
        /// reposition (SPEC.md §4.15's one-time gesture-classification rule).
        case mergeCommitted(markerID: Int)
    }

    private var activeDrag: ActiveDrag?
    private var mouseDownLocation: NSPoint?
    private var mouseDownMarkerID: Int?
    private static let clickVsDragThreshold: CGFloat = 2

    override var isFlipped: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        mouseDownLocation = location
        mouseDownMarkerID = hitTestMarker(at: location)
        activeDrag = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let location = convert(event.locationInWindow, from: nil)

        if activeDrag == nil {
            activeDrag = classifyDragStart(from: start)
        }

        switch activeDrag {
        case let .reposition(markerID):
            if location.y < 0 || location.y > bounds.height {
                // Crossed the vertical bound for the first time — commit to
                // merge-or-cancel; horizontal movement no longer matters.
                activeDrag = .mergeCommitted(markerID: markerID)
            } else {
                let seconds = WaveformCoordinateMapper.secondsAtPixel(
                    location.x,
                    viewWidth: bounds.width,
                    visibleRangeSeconds: visibleRangeSeconds
                )
                onBoundaryDragging?(markerID, seconds)
            }
        case let .pan(startRange, startLocationX):
            let deltaPixels = location.x - startLocationX
            let width = startRange.upperBound - startRange.lowerBound
            let deltaSeconds = -Double(deltaPixels) / Double(max(bounds.width, 1)) * width
            let newRange = WaveformCoordinateMapper.panning(
                startRange,
                byDeltaSeconds: deltaSeconds,
                fileDurationSeconds: fileDurationSeconds
            )
            onPanChanged?(newRange)
        case .mergeCommitted, .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            activeDrag = nil
            mouseDownLocation = nil
            mouseDownMarkerID = nil
        }
        guard let start = mouseDownLocation else { return }
        let location = convert(event.locationInWindow, from: nil)
        let distance = hypot(location.x - start.x, location.y - start.y)

        guard distance > Self.clickVsDragThreshold else {
            handleClick(at: location, modifierFlags: event.modifierFlags)
            return
        }

        switch activeDrag {
        case let .mergeCommitted(markerID):
            onMergeRequested?(markerID)
        case let .reposition(markerID):
            let seconds = WaveformCoordinateMapper.secondsAtPixel(
                location.x,
                viewWidth: bounds.width,
                visibleRangeSeconds: visibleRangeSeconds
            )
            onBoundaryDragged?(markerID, seconds)
        case .pan, .none:
            break
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard visibleRangeSeconds.upperBound - visibleRangeSeconds.lowerBound < fileDurationSeconds else { return }
        let width = visibleRangeSeconds.upperBound - visibleRangeSeconds.lowerBound
        let deltaSeconds = Double(event.scrollingDeltaX) / Double(max(bounds.width, 1)) * width
        onPanChanged?(WaveformCoordinateMapper.panning(
            visibleRangeSeconds,
            byDeltaSeconds: deltaSeconds,
            fileDurationSeconds: fileDurationSeconds
        ))
    }

    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let centerSeconds = WaveformCoordinateMapper.secondsAtPixel(
            location.x,
            viewWidth: bounds.width,
            visibleRangeSeconds: visibleRangeSeconds
        )
        let factor = 1 + event.magnification
        onZoomChanged?(WaveformCoordinateMapper.zooming(
            visibleRangeSeconds,
            by: factor,
            aroundSeconds: centerSeconds,
            fileDurationSeconds: fileDurationSeconds
        ))
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // Grab-cursor affordance only when zoomed in — nothing to pan
        // otherwise (SPEC.md §4.15). Marker-hover-specific cursor swapping
        // is a further refinement left for manual-testing rounds to confirm
        // is actually wanted, not a correctness requirement of this pass.
        if visibleRangeSeconds.upperBound - visibleRangeSeconds.lowerBound < fileDurationSeconds {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    // MARK: - Gesture classification

    private func classifyDragStart(from location: NSPoint) -> ActiveDrag? {
        if let markerID = mouseDownMarkerID {
            return .reposition(markerID: markerID)
        }
        guard visibleRangeSeconds.upperBound - visibleRangeSeconds.lowerBound < fileDurationSeconds else {
            return nil // unzoomed background drag: nothing to pan
        }
        return .pan(startRange: visibleRangeSeconds, startLocationX: location.x)
    }

    private func handleClick(at location: NSPoint, modifierFlags: NSEvent.ModifierFlags) {
        if let markerID = mouseDownMarkerID {
            onPlayMarkerSpan?(markerID)
            return
        }
        let seconds = WaveformCoordinateMapper.secondsAtPixel(
            location.x,
            viewWidth: bounds.width,
            visibleRangeSeconds: visibleRangeSeconds
        )
        if modifierFlags.contains(.option) {
            onSplitRequested?(seconds)
        } else {
            onPlayFromPoint?(seconds)
        }
    }

    private func hitTestMarker(at point: NSPoint) -> Int? {
        markers.first {
            let markerPixelX = WaveformCoordinateMapper.pixelAtSeconds(
                $0.offsetSeconds,
                viewWidth: bounds.width,
                visibleRangeSeconds: visibleRangeSeconds
            )
            return abs(markerPixelX - point.x) <= markerHitRadius
        }?.id
    }
}

/// `NSViewRepresentable` wrapper — plumbs `WaveformView`'s current state
/// into the `NSView` on every SwiftUI update and forwards its callbacks
/// back out as plain closures, no domain type anywhere in this file.
struct WaveformInteractionRepresentable: NSViewRepresentable {
    let visibleRangeSeconds: ClosedRange<Double>
    let fileDurationSeconds: Double
    let markers: [WaveformMarker]
    let onBoundaryDragging: (Int, Double) -> Void
    let onBoundaryDragged: (Int, Double) -> Void
    let onMergeRequested: (Int) -> Void
    let onSplitRequested: (Double) -> Void
    let onPanChanged: (ClosedRange<Double>) -> Void
    let onZoomChanged: (ClosedRange<Double>) -> Void
    let onPlayFromPoint: (Double) -> Void
    let onPlayMarkerSpan: (Int) -> Void

    func makeNSView(context _: Context) -> WaveformInteractionNSView {
        WaveformInteractionNSView()
    }

    func updateNSView(_ nsView: WaveformInteractionNSView, context _: Context) {
        nsView.visibleRangeSeconds = visibleRangeSeconds
        nsView.fileDurationSeconds = fileDurationSeconds
        nsView.markers = markers
        nsView.onBoundaryDragging = onBoundaryDragging
        nsView.onBoundaryDragged = onBoundaryDragged
        nsView.onMergeRequested = onMergeRequested
        nsView.onSplitRequested = onSplitRequested
        nsView.onPanChanged = onPanChanged
        nsView.onZoomChanged = onZoomChanged
        nsView.onPlayFromPoint = onPlayFromPoint
        nsView.onPlayMarkerSpan = onPlayMarkerSpan
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}
