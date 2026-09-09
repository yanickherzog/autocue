@testable import ACDesignSystem
import AppKit
import XCTest

/// Diagnoses the reported merge-gesture bug directly against the real
/// `NSView` subclass, via real `NSEvent`s dispatched through a real
/// (offscreen) `NSWindow`'s responder chain — not a guess, and not
/// `WaveformCoordinateMapper`'s pure math alone, which doesn't exercise
/// `mouseDown`/`mouseDragged`/`mouseUp` at all.
final class WaveformInteractionNSViewTests: XCTestCase {
    /// Not `private`: `WaveformInteractionNSViewTests+BoundaryDragging.swift`
    /// (split into its own file purely to stay under this project's
    /// type-body-length lint limit) needs these two helpers too.
    func makeHostedView(markers: [WaveformMarker]) -> (view: WaveformInteractionNSView, window: NSWindow) {
        let frame = NSRect(x: 0, y: 0, width: 400, height: 160)
        let view = WaveformInteractionNSView(frame: frame)
        view.visibleRangeSeconds = 0 ... 100
        view.fileDurationSeconds = 100
        view.markers = markers

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        return (view, window)
    }

    func mouseEvent(
        type: NSEvent.EventType,
        locationInWindow: NSPoint,
        window: NSWindow
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: locationInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    /// Marker at 50s, in a 400pt-wide view showing 0...100s -> pixel x = 200.
    func test_dragStartingOnMarker_verticallyOffTheBottomEdge_classifiesAsMergeAndFiresOnMouseUp() throws {
        let marker = WaveformMarker(id: 0, offsetSeconds: 50)
        let (view, window) = makeHostedView(markers: [marker])

        var mergeRequestedID: Int?
        view.onMergeRequested = { mergeRequestedID = $0 }
        view.onBoundaryDragged = { _, _ in XCTFail("Should not resolve as reposition") }

        // mouseDown exactly on the marker (x=200, within the 8pt hit radius), mid-strip vertically.
        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        XCTAssertNotNil(view.mouseDownMarkerForTesting, "Precondition: mouseDown must hit-test the marker")

        // Drag straight down, well past the view's bottom edge (height 160).
        try view.mouseDragged(with: mouseEvent(
            type: .leftMouseDragged,
            locationInWindow: NSPoint(x: 200, y: 300),
            window: window
        ))
        XCTAssertEqual(
            view.activeDragDescriptionForTesting,
            "mergeCommitted",
            "Expected the drag to classify as mergeCommitted once it crossed the vertical bound"
        )

        // Release - distance from mouseDown (200,80) to (200,300) is 220pt, well past the click/drag threshold.
        try view.mouseUp(with: mouseEvent(
            type: .leftMouseUp,
            locationInWindow: NSPoint(x: 200, y: 300),
            window: window
        ))

        XCTAssertEqual(mergeRequestedID, 0, "onMergeRequested should have fired with the dragged marker's id")
    }

    func test_dragStartingOnMarker_verticallyOffTheTopEdge_alsoClassifiesAsMerge() throws {
        let marker = WaveformMarker(id: 0, offsetSeconds: 50)
        let (view, window) = makeHostedView(markers: [marker])

        var mergeRequestedID: Int?
        view.onMergeRequested = { mergeRequestedID = $0 }

        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        try view.mouseDragged(with: mouseEvent(
            type: .leftMouseDragged,
            locationInWindow: NSPoint(x: 200, y: -100),
            window: window
        ))
        XCTAssertEqual(view.activeDragDescriptionForTesting, "mergeCommitted")

        try view.mouseUp(with: mouseEvent(
            type: .leftMouseUp,
            locationInWindow: NSPoint(x: 200, y: -100),
            window: window
        ))

        XCTAssertEqual(mergeRequestedID, 0)
    }

    /// A drag that stays horizontal (never crosses the vertical bound)
    /// must still resolve as an ordinary reposition, not a merge - the
    /// control case proving the two paths are genuinely distinguished.
    func test_dragStartingOnMarker_stayingHorizontal_resolvesAsRepositionNotMerge() throws {
        let marker = WaveformMarker(id: 0, offsetSeconds: 50)
        let (view, window) = makeHostedView(markers: [marker])

        var mergeRequestedID: Int?
        var dragged: (WaveformBoundaryMarker, Double)?
        view.onMergeRequested = { mergeRequestedID = $0 }
        view.onBoundaryDragged = { dragged = ($0, $1) }

        try view.mouseDown(with: mouseEvent(
            type: .leftMouseDown,
            locationInWindow: NSPoint(x: 200, y: 80),
            window: window
        ))
        try view.mouseDragged(with: mouseEvent(
            type: .leftMouseDragged,
            locationInWindow: NSPoint(x: 240, y: 80),
            window: window
        ))
        XCTAssertEqual(view.activeDragDescriptionForTesting, "reposition")

        try view.mouseUp(with: mouseEvent(type: .leftMouseUp, locationInWindow: NSPoint(x: 240, y: 80), window: window))

        XCTAssertNil(mergeRequestedID)
        XCTAssertNotNil(dragged)
    }
}
