import AppKit
@testable import AutoCue
import XCTest

/// Direct coverage for `ProjectWindowFrameStore`'s save/read round-trip —
/// isolated via a dedicated `UserDefaults` suite so these tests never touch
/// the real app's `com.autocue.AutoCue` domain.
final class ProjectWindowFrameStoreTests: XCTestCase {
    private let suiteName = "ProjectWindowFrameStoreTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_savedFrame_returnsNilWhenNothingWasEverSaved() {
        XCTAssertNil(ProjectWindowFrameStore.savedFrame(for: UUID(), defaults: defaults))
    }

    func test_saveThenRead_roundTripsExactly() {
        let projectID = UUID()
        let frame = CGRect(x: 111, y: 72, width: 900, height: 650)

        ProjectWindowFrameStore.save(frame, for: projectID, defaults: defaults)

        XCTAssertEqual(ProjectWindowFrameStore.savedFrame(for: projectID, defaults: defaults), frame)
    }

    func test_differentProjectIDs_areStoredIndependently() {
        let projectA = UUID()
        let projectB = UUID()
        ProjectWindowFrameStore.save(CGRect(x: 0, y: 0, width: 400, height: 300), for: projectA, defaults: defaults)
        ProjectWindowFrameStore.save(CGRect(x: 50, y: 50, width: 900, height: 700), for: projectB, defaults: defaults)

        XCTAssertEqual(
            ProjectWindowFrameStore.savedFrame(for: projectA, defaults: defaults),
            CGRect(x: 0, y: 0, width: 400, height: 300)
        )
        XCTAssertEqual(
            ProjectWindowFrameStore.savedFrame(for: projectB, defaults: defaults),
            CGRect(x: 50, y: 50, width: 900, height: 700)
        )
    }
}

/// Exercises `ProjectWindowFrameSaver` against a real `NSWindow` and real
/// `NotificationCenter`/`UserDefaults` (isolated suite) — deliberately not a
/// synthesized UI interaction (this environment has no Accessibility
/// permission to drive one); this is the actual save mechanism running for
/// real, which is what needed proving after `NSWindow.setFrameAutosaveName`
/// was found not to work at all.
///
/// **Posts `NSWindow.willCloseNotification` manually rather than calling
/// `window.close()`.** A first version of this test called `.close()` on a
/// real, programmatically-created `NSWindow` and reliably crashed —
/// confirmed via a real crash report (`AutoCue-2026-08-10-112543.ips`), not
/// guessed at: `EXC_BAD_ACCESS`/`SIGSEGV` inside `objc_release`, during
/// XCTest's own post-test `-[XCTestCase
/// assertInvalidObjectsDeallocatedAfterScope:]` memory-deallocation check —
/// a known category of friction between XCTest's instrumentation and real
/// AppKit window-close teardown in a test host, not a bug in
/// `ProjectWindowFrameSaver` (a control test that creates a window and
/// never closes it passes cleanly). Posting the exact notification
/// `ProjectWindowFrameSaver` observes exercises the same code path (the
/// thing actually being tested — does the observer correctly read the
/// window's frame and save it) without going through AppKit's real
/// `close()` teardown, which isn't this project's code to test in the
/// first place.
@MainActor
final class ProjectWindowFrameSaverTests: XCTestCase {
    private let suiteName = "ProjectWindowFrameSaverTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_windowClosing_savesItsFrameForTheGivenProjectID() {
        let projectID = UUID()
        let window = NSWindow(
            contentRect: NSRect(x: 42, y: 84, width: 820, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let expectedFrame = window.frame
        let saver = ProjectWindowFrameSaver(window: window, projectID: projectID, defaults: defaults)

        XCTAssertNil(ProjectWindowFrameStore.savedFrame(for: projectID, defaults: defaults))

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

        XCTAssertEqual(ProjectWindowFrameStore.savedFrame(for: projectID, defaults: defaults), expectedFrame)
        _ = saver // keep alive until after the assertion
    }

    func test_windowNeverClosing_savesNothing() {
        let projectID = UUID()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let saver = ProjectWindowFrameSaver(window: window, projectID: projectID, defaults: defaults)

        XCTAssertNil(ProjectWindowFrameStore.savedFrame(for: projectID, defaults: defaults))
        _ = saver
    }

    func test_deallocatingTheSaver_stopsObservingFurtherCloses() {
        let projectID = UUID()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        var saver: ProjectWindowFrameSaver? = ProjectWindowFrameSaver(
            window: window,
            projectID: projectID,
            defaults: defaults
        )
        saver = nil
        _ = saver

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

        XCTAssertNil(ProjectWindowFrameStore.savedFrame(for: projectID, defaults: defaults))
    }
}
