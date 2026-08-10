import ACCore
import AppKit
import Foundation

/// Saves a Project window's frame to `ProjectWindowFrameStore` the moment
/// it's about to close (`ROADMAP.md` D6, manual verification follow-up).
///
/// Observes `NSWindow.willCloseNotification` scoped to the specific window
/// instance, rather than becoming `window.delegate` — `delegate` is a
/// single slot AppKit/SwiftUI may already be using internally for
/// `WindowGroup(for:)`'s own state management, and overwriting it wholesale
/// risks silently breaking whatever else relies on it. `willCloseNotification`
/// is the same underlying event a delegate's `windowWillClose(_:)` would
/// observe, without requiring exclusive ownership of the delegate slot.
///
/// Must be retained for as long as the window it's watching exists —
/// `NotificationCenter` observer tokens don't keep themselves alive.
/// `ProjectWindowView` holds one via `@State`, the same "one owner per
/// window" pattern already used for that view's `AppState`.
final class ProjectWindowFrameSaver {
    private var observer: NSObjectProtocol?

    init(window: NSWindow, projectID: Project.ID, defaults: UserDefaults = .standard) {
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            ProjectWindowFrameStore.save(window.frame, for: projectID, defaults: defaults)
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
