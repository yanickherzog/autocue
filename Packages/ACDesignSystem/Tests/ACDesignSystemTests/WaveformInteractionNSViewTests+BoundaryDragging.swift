@testable import ACDesignSystem
import AppKit
import XCTest

/// Independent end markers, the contiguous tie-break, push-through live
/// preview, and the grab/release highlight signal (SPEC.md §4.19) — split
/// into its own file/extension purely to keep `WaveformInteractionNSViewTests`
/// under this project's type-body-length lint limit, the same reason
/// `WaveformInteractionNSView` itself splits its boundary hit-testing into
/// `WaveformInteractionView+BoundaryHitTesting.swift`. Reuses that class's
/// `makeHostedView`/`mouseEvent` helpers, made non-`private` there
/// specifically so this file can share them.
extension WaveformInteractionNSViewTests {
    /// Two markers, a real gap between them: cue 0 spans 40...50s (end 50),
    /// cue 1 starts at 60s — 400pt view over 0...100s -> 1pt == 0.25s, so
    /// cue 0's end (50s) is pixel x=200, cue 1's start (60s) is x=240, well
    /// outside each other's 8pt hit radius.
    func test_dragEndMarker_nonContiguous_resolvesIndependentlyOfNeighborsStartMarker() throws {
        let marker0 = WaveformMarker(id: 0, offsetSeconds: 40, durationSeconds: 10) // end 50
        let marker1 = WaveformMarker(id: 1, offsetSeconds: 60, durationSeconds: 10)
        let (view, window) = makeHostedView(markers: [marker0, marker1])

        var dragged: (WaveformBoundaryMarker, Double)?
        view.onBoundaryDragged = { dragged = ($0, $1) }

        // mouseDown at x=200 (cue 0's end, 50s).
        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        XCTAssertEqual(view.mouseDownMarkerForTesting, .end(cueIndex: 0))

        try view.mouseDragged(with: mouseEvent(
            type: .leftMouseDragged,
            locationInWindow: NSPoint(x: 220, y: 80),
            window: window
        ))
        try view.mouseUp(with: mouseEvent(type: .leftMouseUp, locationInWindow: NSPoint(x: 220, y: 80), window: window))

        XCTAssertEqual(dragged?.0, .end(cueIndex: 0))
    }

    /// Cue 0 spans 40...50s, cue 1 starts exactly at 50s — genuinely
    /// touching. Both cue 0's end and cue 1's start land on the same pixel
    /// (x=200); the following cue's start marker must win the tie.
    func test_hitTest_contiguousBoundary_prefersFollowingCuesStartMarker() throws {
        let marker0 = WaveformMarker(id: 0, offsetSeconds: 40, durationSeconds: 10) // end 50
        let marker1 = WaveformMarker(id: 1, offsetSeconds: 50, durationSeconds: 10)
        let (view, window) = makeHostedView(markers: [marker0, marker1])

        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))

        XCTAssertEqual(view.mouseDownMarkerForTesting, .start(cueIndex: 1))
    }

    /// `onMarkerGrabbed` must fire the instant a marker is hit-tested, at
    /// `mouseDown`, before any drag motion — this is what lets the host
    /// highlight which cue a coincident tie-break actually resolved to
    /// immediately, not only once the user has already started dragging.
    /// `onMarkerReleased` must then fire on `mouseUp` even for a plain click
    /// (no real drag), so the highlight never gets stuck on.
    func test_markerGrabbedAndReleased_firesOnMouseDownAndMouseUp_evenForAPlainClick() throws {
        let marker0 = WaveformMarker(id: 0, offsetSeconds: 40, durationSeconds: 10) // end 50
        let marker1 = WaveformMarker(id: 1, offsetSeconds: 50, durationSeconds: 10)
        let (view, window) = makeHostedView(markers: [marker0, marker1])

        var grabbed: WaveformBoundaryMarker?
        var releasedCount = 0
        view.onMarkerGrabbed = { grabbed = $0 }
        view.onMarkerReleased = { releasedCount += 1 }
        view.onPlayMarkerSpan = { _ in } // absorb the click-to-play-span this resolves as

        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        XCTAssertEqual(grabbed, .start(cueIndex: 1), "Grabbed the tie-break winner immediately, before any movement")
        XCTAssertEqual(releasedCount, 0)

        // A plain click — no real drag distance — still must release the highlight.
        try view.mouseUp(with: mouseEvent(type: .leftMouseUp, locationInWindow: NSPoint(x: 200, y: 80), window: window))
        XCTAssertEqual(releasedCount, 1)
    }

    /// Same touching pair as above. The tie-break resolves the grab to cue
    /// 1's start marker; dragging *left*, into cue 0's territory, is that
    /// marker's push-through direction (the mirror image of dragging an end
    /// marker right into its successor) — SPEC.md §4.19's atomic contiguous
    /// push-through. Must fire a live preview for both markers, not just the
    /// one grabbed.
    func test_dragContiguousBoundary_pushingThrough_previewsBothMarkersMovingTogether() throws {
        let marker0 = WaveformMarker(id: 0, offsetSeconds: 40, durationSeconds: 10) // end 50, touches marker1
        let marker1 = WaveformMarker(id: 1, offsetSeconds: 50, durationSeconds: 20) // own end 70
        let (view, window) = makeHostedView(markers: [marker0, marker1])

        var previews: [WaveformBoundaryMarker: Double] = [:]
        view.onBoundaryDragging = { previews[$0] = $1 }

        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        XCTAssertEqual(view.mouseDownMarkerForTesting, .start(cueIndex: 1)) // the tie-break from above

        // Drag left, past the touching point (200, 50s) toward cue 0's own
        // start (40s -> x=160) — pushing through, not just approaching.
        try view.mouseDragged(with: mouseEvent(
            type: .leftMouseDragged,
            locationInWindow: NSPoint(x: 180, y: 80),
            window: window
        ))

        XCTAssertEqual(try XCTUnwrap(previews[.start(cueIndex: 1)]), 45, accuracy: 0.01) // the grabbed marker itself
        XCTAssertEqual(try XCTUnwrap(previews[.end(cueIndex: 0)]), 45, accuracy: 0.01) // carried along, coupled
    }

    /// Reported bug repro: dragging a NON-contiguous end marker toward the
    /// next cue's start must clamp the *live preview* at exactly the
    /// neighbor's current position — it must never overshoot, even though
    /// the raw cursor position (75s here) is well past the neighbor's start
    /// (60s). SPEC.md §4.19's "clamps at exactly zero gap... continuing to
    /// hold/drag has no further effect" describes the *visible* drag, not
    /// just the eventual persisted result.
    func test_dragNonContiguousEndMarker_towardNeighbor_livePreviewClampsAtNeighborsPosition() throws {
        let marker0 = WaveformMarker(id: 0, offsetSeconds: 40, durationSeconds: 10) // end 50
        let marker1 = WaveformMarker(id: 1, offsetSeconds: 60, durationSeconds: 10) // real 10s gap
        let (view, window) = makeHostedView(markers: [marker0, marker1])

        var previews: [Double] = []
        view.onBoundaryDragging = { marker, seconds in
            XCTAssertEqual(marker, .end(cueIndex: 0))
            previews.append(seconds)
        }

        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        XCTAssertEqual(view.mouseDownMarkerForTesting, .end(cueIndex: 0))

        // Drag to x=300 (75s) — well past the neighbor's start (60s, x=240).
        try view.mouseDragged(with: mouseEvent(
            type: .leftMouseDragged,
            locationInWindow: NSPoint(x: 300, y: 80),
            window: window
        ))

        XCTAssertEqual(previews.last, 60, "Live preview must clamp at the neighbor's position, never overshoot")
    }

    /// Same repro, the other free-standing case: the very last cue's end
    /// marker has no successor at all — its live preview must clamp at the
    /// file's own duration, not follow the raw cursor past the end of the
    /// file.
    func test_dragLastCuesEndMarker_noSuccessor_livePreviewClampsAtFileDuration() throws {
        let onlyMarker = WaveformMarker(id: 0, offsetSeconds: 40, durationSeconds: 10) // end 50
        let (view, window) = makeHostedView(markers: [onlyMarker])
        view.fileDurationSeconds = 60

        var previews: [Double] = []
        view.onBoundaryDragging = { _, seconds in previews.append(seconds) }

        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        // Drag to x=380 (95s) — well past the file's own 60s duration.
        try view.mouseDragged(with: mouseEvent(
            type: .leftMouseDragged,
            locationInWindow: NSPoint(x: 380, y: 80),
            window: window
        ))

        XCTAssertEqual(previews.last, 60, "Live preview must clamp at the file's own duration, never overshoot it")
    }

    /// The very first cue's start marker has no predecessor at all — its
    /// live preview must clamp at the file's own start (0), not follow the
    /// raw cursor into negative offsets.
    func test_dragFirstCuesStartMarker_noPredecessor_livePreviewClampsAtZero() throws {
        let onlyMarker = WaveformMarker(id: 0, offsetSeconds: 40, durationSeconds: 10) // end 50
        let (view, window) = makeHostedView(markers: [onlyMarker])

        var previews: [Double] = []
        view.onBoundaryDragging = { _, seconds in previews.append(seconds) }

        // Grab the *start* edge specifically: pixel x=160 (40s), not the
        // coincident-with-nothing end at x=200 (50s, no neighbor to tie with anyway).
        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 160, y: 80),
            window: window
        ))
        XCTAssertEqual(view.mouseDownMarkerForTesting, .start(cueIndex: 0))
        // Drag to x=-40 (-10s) — well past the file's own start.
        try view.mouseDragged(with: mouseEvent(
            type: .leftMouseDragged,
            locationInWindow: NSPoint(x: -40, y: 80),
            window: window
        ))

        XCTAssertEqual(previews.last, 0, "Live preview must clamp at the file's own start (0), never go negative")
    }

    /// Dragging the same touching boundary *away* (opening a gap) must
    /// never carry the neighbor along — only a single-marker preview fires.
    func test_dragContiguousBoundary_pullingApart_previewsOnlyTheGrabbedMarker() throws {
        let marker0 = WaveformMarker(id: 0, offsetSeconds: 40, durationSeconds: 10) // end 50, touches marker1
        let marker1 = WaveformMarker(id: 1, offsetSeconds: 50, durationSeconds: 20)
        let (view, window) = makeHostedView(markers: [marker0, marker1])

        var previews: [WaveformBoundaryMarker: Double] = [:]
        view.onBoundaryDragging = { previews[$0] = $1 }

        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        XCTAssertEqual(view.mouseDownMarkerForTesting, .start(cueIndex: 1))

        // Drag right — for cue 1's own start marker, moving right shrinks
        // cue 1 from the front, opening a gap before it (SPEC.md §4.19),
        // the "away" direction for this particular marker.
        try view.mouseDragged(with: mouseEvent(
            type: .leftMouseDragged,
            locationInWindow: NSPoint(x: 220, y: 80),
            window: window
        ))

        XCTAssertEqual(try XCTUnwrap(previews[.start(cueIndex: 1)]), 55, accuracy: 0.01)
        XCTAssertNil(previews[.end(cueIndex: 0)]) // never carried along while pulling apart
    }
}
