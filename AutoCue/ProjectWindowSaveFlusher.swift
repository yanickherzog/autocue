import ACFeatures
import AppKit
import Foundation

/// Flushes any pending debounced Setup save the moment a Project window is
/// about to close (`ROADMAP.md` D7, post-click-through fix).
///
/// Same `NSWindow.willCloseNotification` mechanism as `ProjectWindowFrameSaver`,
/// for the identical reason: SwiftUI's `.onDisappear` is not reliably
/// triggered by a real window close in this `WindowGroup(for:)` context —
/// `ProjectWindowFrameSaver`'s own doc comment already establishes this
/// finding; this reuses it rather than re-discovering it. Without this, a
/// debounced `SetupViewModel` edit still in flight when the window closes
/// (e.g. the user types a title, then immediately hits ⌘W before the 500ms
/// debounce elapses) could be lost — `SetupViewModel.flushPendingSave()` is
/// exactly the method that exists to prevent that, it just needs a reliable
/// trigger at window-close time, same as the frame does.
///
/// Observes rather than becomes `window.delegate`, for the same reason
/// `ProjectWindowFrameSaver` does — see its doc comment.
final class ProjectWindowSaveFlusher {
    private var observer: NSObjectProtocol?

    init(window: NSWindow, setupViewModel: SetupViewModel) {
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { await setupViewModel.flushPendingSave() }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
