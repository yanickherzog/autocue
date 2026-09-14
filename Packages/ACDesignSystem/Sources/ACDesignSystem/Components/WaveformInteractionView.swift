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
    /// one, single commit point. May fire twice per drag frame while
    /// pushing through an already-contiguous boundary (SPEC.md §4.19) — once
    /// for the grabbed marker, once for the neighbor being carried along —
    /// so the host can preview both moving together, not just the one
    /// actually grabbed.
    var onBoundaryDragging: ((WaveformBoundaryMarker, Double) -> Void)?
    var onBoundaryDragged: ((WaveformBoundaryMarker, Double) -> Void)?
    /// Fired the instant a marker is hit-tested at `mouseDown` — *before*
    /// any drag motion, so the host can highlight which cue a coincident
    /// (zero-gap) tie-break actually resolved to right away, not only once
    /// the user has already started moving the mouse (SPEC.md §4.19).
    /// `onMarkerReleased` always fires on `mouseUp`, regardless of gesture
    /// outcome (click, reposition commit, merge, or pan/none), so a plain
    /// click-to-play-span never leaves the highlight stuck on.
    var onMarkerGrabbed: ((WaveformBoundaryMarker) -> Void)?
    var onMarkerReleased: (() -> Void)?
    var onMergeRequested: ((Int) -> Void)?
    var onSplitRequested: ((Double) -> Void)?
    var onPanChanged: ((ClosedRange<Double>) -> Void)?
    var onZoomChanged: ((ClosedRange<Double>) -> Void)?
    var onPlayFromPoint: ((Double) -> Void)?
    var onPlayMarkerSpan: ((Int) -> Void)?

    private enum ActiveDrag {
        case pan(startRange: ClosedRange<Double>, startLocationX: CGFloat)
        case reposition(marker: WaveformBoundaryMarker)
        /// Classified once a reposition drag crosses the strip's vertical
        /// bounds — from this point on, horizontal movement is ignored and
        /// the gesture resolves to merge-or-cancel on release, never back to
        /// reposition (SPEC.md §4.15's one-time gesture-classification rule).
        case mergeCommitted(marker: WaveformBoundaryMarker)
    }

    private var activeDrag: ActiveDrag?
    private var mouseDownLocation: NSPoint?
    private var mouseDownMarker: WaveformBoundaryMarker?
    private static let clickVsDragThreshold: CGFloat = 2

    /// The marker a click-to-play (`handleClick`'s `onPlayMarkerSpan` branch)
    /// most recently targeted, and when — sidesteps a real, reproduced race
    /// (2026-09-14) rather than fixing its root cause, which wasn't pinned
    /// down at the AppKit/event-delivery level: starting a *new* gesture on
    /// the *same* marker shortly after that marker's own click just started
    /// playback could leave `mouseDragged`/`mouseUp` never arriving for that
    /// gesture at all, corrupting this view's tracking state
    /// (`activeDrag`/`mouseDownMarker`) and the host's `grabbedMarker`
    /// highlight indefinitely — the marker's span stuck visibly "active,"
    /// un-draggable, with nothing to undo since the drag's own completion
    /// event never arrived to report anything to undo in the first place.
    private var recentPlayTriggerMarker: WaveformBoundaryMarker?
    private var recentPlayTriggerTime: TimeInterval?
    /// Real observed failure gap between the triggering click and the
    /// corrupted gesture's own `mouseDown`: ~105ms. 200ms leaves ~2x margin
    /// above that while staying comfortably under the ~200-250ms floor for
    /// even a *reflex* human reaction to an unexpected stimulus (hearing
    /// playback start unexpectedly) — a genuine, deliberate retry (perceive
    /// the mistake, decide to retry, move the mouse back, click again)
    /// realistically takes well over that. Deliberately blocks a second
    /// click-to-play on the same marker within the window too, not only a
    /// drag — only click-then-*drag* was directly captured failing, but the
    /// corruption point (right after `onMarkerGrabbed`, before `mouseUp`)
    /// doesn't obviously depend on the second gesture becoming a drag
    /// specifically, and treating both uniformly is the conservative choice
    /// given that uncertainty. A same-marker click swallowed this way still
    /// falls through to `onPlayFromPoint` at that same position (still
    /// starts playback from the same point, just unbounded rather than
    /// stopped at the cue's own end) — a graceful fallback, not a dead click.
    private static let sameMarkerGestureCooldownSeconds: TimeInterval = 0.2

    /// Extracted purely so `mouseDown`'s own `if` doesn't need a multi-line
    /// condition (this project's SwiftFormat/SwiftLint configuration
    /// disagree on brace placement for those) — no behavior beyond what
    /// `mouseDown`'s doc comment above already describes.
    private func isSameMarkerCooldownActive(for marker: WaveformBoundaryMarker) -> Bool {
        guard marker == recentPlayTriggerMarker, let recentPlayTriggerTime else { return false }
        return ProcessInfo.processInfo.systemUptime - recentPlayTriggerTime < Self.sameMarkerGestureCooldownSeconds
    }

    /// Test-only, read-only diagnostic accessors — `internal`, not exposed
    /// as public API; `@testable import` reaches these but nothing outside
    /// the package can. Added while diagnosing the reported merge-gesture
    /// bug so the test can assert on gesture classification directly rather
    /// than only on its downstream effect.
    var mouseDownMarkerForTesting: WaveformBoundaryMarker? {
        mouseDownMarker
    }

    var activeDragDescriptionForTesting: String? {
        switch activeDrag {
        case .reposition: "reposition"
        case .mergeCommitted: "mergeCommitted"
        case .pan: "pan"
        case nil: nil
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        mouseDownLocation = location
        let hitMarker = hitTestMarker(at: location)
        if let hitMarker, isSameMarkerCooldownActive(for: hitMarker) {
            // Cooldown active for this exact marker — treat as if no marker
            // was hit, sidestepping the race rather than chasing its root
            // cause. Falls through to background click/pan handling.
            mouseDownMarker = nil
        } else {
            mouseDownMarker = hitMarker
        }
        activeDrag = nil
        if let mouseDownMarker {
            onMarkerGrabbed?(mouseDownMarker)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let location = convert(event.locationInWindow, from: nil)

        if activeDrag == nil {
            activeDrag = classifyDragStart(from: start)
        }

        switch activeDrag {
        case let .reposition(marker):
            if location.y < 0 || location.y > bounds.height {
                // Crossed the vertical bound for the first time — commit to
                // merge-or-cancel; horizontal movement no longer matters.
                activeDrag = .mergeCommitted(marker: marker)
            } else {
                let seconds = WaveformCoordinateMapper.secondsAtPixel(
                    location.x,
                    viewWidth: bounds.width,
                    visibleRangeSeconds: visibleRangeSeconds
                )
                previewDrag(of: marker, toSeconds: seconds)
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
            mouseDownMarker = nil
            onMarkerReleased?()
        }
        guard let start = mouseDownLocation else { return }
        let location = convert(event.locationInWindow, from: nil)
        let distance = hypot(location.x - start.x, location.y - start.y)

        guard distance > Self.clickVsDragThreshold else {
            handleClick(at: location, modifierFlags: event.modifierFlags)
            return
        }

        switch activeDrag {
        case let .mergeCommitted(marker):
            onMergeRequested?(followingCueIndex(for: marker))
        case let .reposition(marker):
            let seconds = WaveformCoordinateMapper.secondsAtPixel(
                location.x,
                viewWidth: bounds.width,
                visibleRangeSeconds: visibleRangeSeconds
            )
            onBoundaryDragged?(marker, seconds)
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
        if let marker = mouseDownMarker {
            return .reposition(marker: marker)
        }
        guard visibleRangeSeconds.upperBound - visibleRangeSeconds.lowerBound < fileDurationSeconds else {
            return nil // unzoomed background drag: nothing to pan
        }
        return .pan(startRange: visibleRangeSeconds, startLocationX: location.x)
    }

    private func handleClick(at location: NSPoint, modifierFlags: NSEvent.ModifierFlags) {
        if let marker = mouseDownMarker {
            recentPlayTriggerMarker = marker
            recentPlayTriggerTime = ProcessInfo.processInfo.systemUptime
            onPlayMarkerSpan?(cueIndex(for: marker))
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
}

/// `NSViewRepresentable` wrapper — plumbs `WaveformView`'s current state
/// into the `NSView` on every SwiftUI update and forwards its callbacks
/// back out as plain closures, no domain type anywhere in this file.
struct WaveformInteractionRepresentable: NSViewRepresentable {
    let visibleRangeSeconds: ClosedRange<Double>
    let fileDurationSeconds: Double
    let markers: [WaveformMarker]
    let onBoundaryDragging: (WaveformBoundaryMarker, Double) -> Void
    let onBoundaryDragged: (WaveformBoundaryMarker, Double) -> Void
    let onMarkerGrabbed: (WaveformBoundaryMarker) -> Void
    let onMarkerReleased: () -> Void
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
        nsView.onMarkerGrabbed = onMarkerGrabbed
        nsView.onMarkerReleased = onMarkerReleased
        nsView.onMergeRequested = onMergeRequested
        nsView.onSplitRequested = onSplitRequested
        nsView.onPanChanged = onPanChanged
        nsView.onZoomChanged = onZoomChanged
        nsView.onPlayFromPoint = onPlayFromPoint
        nsView.onPlayMarkerSpan = onPlayMarkerSpan
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}
