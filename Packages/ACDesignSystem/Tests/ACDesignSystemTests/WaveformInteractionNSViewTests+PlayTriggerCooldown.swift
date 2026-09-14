@testable import ACDesignSystem
import AppKit
import XCTest

/// The same-marker gesture cooldown that sidesteps a real, reproduced race
/// (2026-09-14): a click-to-play on a marker followed immediately by a new
/// gesture on that *same* marker could leave `mouseDragged`/`mouseUp` never
/// arriving, corrupting the view's gesture-tracking state indefinitely.
/// Split into its own file for the same reason `+BoundaryDragging.swift`
/// is — reuses `WaveformInteractionNSViewTests`'s `makeHostedView`/
/// `mouseEvent` helpers.
extension WaveformInteractionNSViewTests {
    /// Marker at 50s in a 400pt view over 0...100s -> pixel x=200 (matches
    /// `makeHostedView`'s own convention).
    func test_newDragOnSameMarker_immediatelyAfterItsOwnClickToPlay_isSuppressed() throws {
        let marker = WaveformMarker(id: 0, offsetSeconds: 50)
        let (view, window) = makeHostedView(markers: [marker])

        var playedMarkerSpanID: Int?
        var dragged: (WaveformBoundaryMarker, Double)?
        view.onPlayMarkerSpan = { playedMarkerSpanID = $0 }
        view.onBoundaryDragged = { dragged = ($0, $1) }

        // Plain click on the marker -- triggers click-to-play.
        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        try view.mouseUp(with: mouseEvent(type: .leftMouseUp, locationInWindow: NSPoint(x: 200, y: 80), window: window))
        XCTAssertEqual(playedMarkerSpanID, 0, "Precondition: the click must have triggered click-to-play")

        // Immediately (no real time passes in a unit test) attempt a real
        // drag on the SAME marker -- must be suppressed, not corrupted.
        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        XCTAssertNil(
            view.mouseDownMarkerForTesting,
            "Cooldown active: this mouseDown must resolve as if no marker was hit"
        )

        try view.mouseDragged(with: mouseEvent(
            type: .leftMouseDragged,
            locationInWindow: NSPoint(x: 240, y: 80),
            window: window
        ))
        try view.mouseUp(with: mouseEvent(type: .leftMouseUp, locationInWindow: NSPoint(x: 240, y: 80), window: window))

        XCTAssertNil(dragged, "The suppressed gesture must never resolve as a reposition")
    }

    /// A second click-to-play on the SAME marker within the cooldown falls
    /// through to `onPlayFromPoint` at that position (still starts playback
    /// from the same point, just unbounded) rather than either re-firing
    /// `onPlayMarkerSpan` or being silently swallowed -- a deliberate,
    /// documented choice (`WaveformInteractionNSView`'s own doc comment):
    /// only click-then-drag was directly confirmed to corrupt state, but the
    /// corruption point doesn't obviously depend on the second gesture
    /// becoming a drag, so both are treated the same, conservatively.
    func test_secondClickToPlaySameMarker_withinCooldown_fallsThroughToPlayFromPoint() throws {
        let marker = WaveformMarker(id: 0, offsetSeconds: 50)
        let (view, window) = makeHostedView(markers: [marker])

        var playMarkerSpanCallCount = 0
        var playFromPointSeconds: Double?
        view.onPlayMarkerSpan = { _ in playMarkerSpanCallCount += 1 }
        view.onPlayFromPoint = { playFromPointSeconds = $0 }

        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        try view.mouseUp(with: mouseEvent(type: .leftMouseUp, locationInWindow: NSPoint(x: 200, y: 80), window: window))
        XCTAssertEqual(playMarkerSpanCallCount, 1)

        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        try view.mouseUp(with: mouseEvent(type: .leftMouseUp, locationInWindow: NSPoint(x: 200, y: 80), window: window))

        XCTAssertEqual(playMarkerSpanCallCount, 1, "Must not re-trigger onPlayMarkerSpan during the cooldown")
        XCTAssertNotNil(playFromPointSeconds, "Must fall through to a still-functional alternative, not a dead click")
    }

    /// Dragging a DIFFERENT marker immediately after another marker's
    /// click-to-play must be completely unaffected -- the cooldown is scoped
    /// to the exact marker that was just triggered, not the whole view.
    func test_dragOnDifferentMarker_immediatelyAfterAnothersClickToPlay_worksNormally() throws {
        let markerA = WaveformMarker(id: 0, offsetSeconds: 50)
        let markerB = WaveformMarker(id: 1, offsetSeconds: 80)
        let (view, window) = makeHostedView(markers: [markerA, markerB])

        var playedMarkerSpanID: Int?
        var dragged: (WaveformBoundaryMarker, Double)?
        view.onPlayMarkerSpan = { playedMarkerSpanID = $0 }
        view.onBoundaryDragged = { dragged = ($0, $1) }

        // Click marker A (50s -> x=200) to trigger playback.
        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        try view.mouseUp(with: mouseEvent(type: .leftMouseUp, locationInWindow: NSPoint(x: 200, y: 80), window: window))
        XCTAssertEqual(playedMarkerSpanID, 0)

        // Immediately drag marker B (80s -> x=320) -- unaffected by A's cooldown.
        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 320, y: 80),
            window: window
        ))
        XCTAssertEqual(view.mouseDownMarkerForTesting, .start(cueIndex: 1))

        try view.mouseDragged(with: mouseEvent(
            type: .leftMouseDragged,
            locationInWindow: NSPoint(x: 340, y: 80),
            window: window
        ))
        try view.mouseUp(with: mouseEvent(type: .leftMouseUp, locationInWindow: NSPoint(x: 340, y: 80), window: window))

        XCTAssertNotNil(dragged, "A different marker's drag must not be swallowed")
        XCTAssertEqual(dragged?.0, .start(cueIndex: 1))
    }

    /// Once the real cooldown window has genuinely elapsed, a fresh gesture
    /// on the same marker must work normally again -- the suppression is a
    /// brief window, not a lasting lockout.
    func test_dragOnSameMarker_afterCooldownElapses_worksNormally() throws {
        let marker = WaveformMarker(id: 0, offsetSeconds: 50)
        let (view, window) = makeHostedView(markers: [marker])

        var playedMarkerSpanID: Int?
        var dragged: (WaveformBoundaryMarker, Double)?
        view.onPlayMarkerSpan = { playedMarkerSpanID = $0 }
        view.onBoundaryDragged = { dragged = ($0, $1) }

        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        try view.mouseUp(with: mouseEvent(type: .leftMouseUp, locationInWindow: NSPoint(x: 200, y: 80), window: window))
        XCTAssertEqual(playedMarkerSpanID, 0)

        // Real wall-clock wait, comfortably past the 200ms cooldown -- the
        // cooldown is measured against real elapsed time, not event
        // timestamps, so this has to be a genuine sleep, not a synthetic one.
        Thread.sleep(forTimeInterval: 0.35)

        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        XCTAssertEqual(view.mouseDownMarkerForTesting, .start(cueIndex: 0), "Cooldown must have expired by now")

        try view.mouseDragged(with: mouseEvent(
            type: .leftMouseDragged,
            locationInWindow: NSPoint(x: 240, y: 80),
            window: window
        ))
        try view.mouseUp(with: mouseEvent(type: .leftMouseUp, locationInWindow: NSPoint(x: 240, y: 80), window: window))

        XCTAssertNotNil(dragged, "A genuine retry after the cooldown must succeed normally")
    }
}
