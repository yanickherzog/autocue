import AppKit
@testable import AutoCue
import XCTest

/// Direct coverage for `OpenProjectWindowRegistry`'s register/unregister/
/// lookup/focus logic — plain state, not SwiftUI-dependent, so it's
/// testable without a UI test (`ROADMAP.md` D6/T6.1's own Testing
/// Requirements). The multi-window focus-not-duplicate *behavior* itself is
/// manually verified, per the same section.
@MainActor
final class OpenProjectWindowRegistryTests: XCTestCase {
    /// Records whether `makeKeyAndOrderFront(_:)` was called, so `focus(_:)`
    /// can be verified without a real window server.
    private final class RecordingWindow: NSWindow {
        private(set) var didCallMakeKeyAndOrderFront = false

        override func makeKeyAndOrderFront(_: Any?) {
            didCallMakeKeyAndOrderFront = true
        }
    }

    func test_isOpen_forNeverRegisteredID_returnsFalse() {
        let registry = OpenProjectWindowRegistry()
        XCTAssertFalse(registry.isOpen(UUID()))
    }

    func test_register_thenIsOpen_returnsTrue() {
        let registry = OpenProjectWindowRegistry()
        let id = UUID()

        registry.register(id, window: RecordingWindow())

        XCTAssertTrue(registry.isOpen(id))
    }

    func test_unregister_thenIsOpen_returnsFalse() {
        let registry = OpenProjectWindowRegistry()
        let id = UUID()
        registry.register(id, window: RecordingWindow())

        registry.unregister(id)

        XCTAssertFalse(registry.isOpen(id))
    }

    func test_registeringADifferentID_doesNotAffectAnAlreadyRegisteredID() {
        let registry = OpenProjectWindowRegistry()
        let firstID = UUID()
        let secondID = UUID()
        registry.register(firstID, window: RecordingWindow())

        registry.register(secondID, window: RecordingWindow())

        XCTAssertTrue(registry.isOpen(firstID))
        XCTAssertTrue(registry.isOpen(secondID))
    }

    func test_focus_bringsTheRegisteredWindowToFront() {
        let registry = OpenProjectWindowRegistry()
        let id = UUID()
        let window = RecordingWindow()
        registry.register(id, window: window)

        registry.focus(id)

        XCTAssertTrue(window.didCallMakeKeyAndOrderFront)
    }

    func test_focus_forAnUnregisteredID_doesNothing() {
        // Must not crash — the "focus" call site should only ever be
        // reached after checking isOpen(_:) first, but the method itself
        // stays safe to call regardless.
        let registry = OpenProjectWindowRegistry()
        registry.focus(UUID())
    }
}
