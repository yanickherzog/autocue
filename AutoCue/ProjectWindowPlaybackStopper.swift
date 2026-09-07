import ACFeatures
import AppKit
import Foundation

/// Stops any playback `CueDetectionReviewViewModel` started, the moment this
/// Project window is about to close. Real, reproduced bug, not a
/// hypothetical: closing a Project window while audio was playing left it
/// running and audible with no way to stop it, since the play/stop button
/// and spacebar handler live in the now-closed window.
///
/// Same `NSWindow.willCloseNotification` mechanism as
/// `ProjectWindowFrameSaver`/`ProjectWindowSaveFlusher`, for the identical
/// reason: SwiftUI's `.onDisappear` is not reliably triggered by a real
/// window close in this `WindowGroup(for:)` context — see either of those
/// types' doc comments for that finding, not rediscovered here. There was
/// previously no teardown hook at all for playback: `CueDetectionReviewViewModel
/// .deinit` cancels its own tasks but was never able to reach
/// `AudioPlaybackController.stop()` (an `async` actor method, from a
/// synchronous `deinit`), and `AudioPlaybackControllerImpl.deinit` only tears
/// down its poll task and security-scoped access — not the player itself.
///
/// Observes rather than becomes `window.delegate`, for the same reason
/// `ProjectWindowFrameSaver` does — see its doc comment.
final class ProjectWindowPlaybackStopper {
    private var observer: NSObjectProtocol?

    init(window: NSWindow, cueDetectionReviewViewModel: CueDetectionReviewViewModel) {
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { await cueDetectionReviewViewModel.stopPlaybackForWindowClose() }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
