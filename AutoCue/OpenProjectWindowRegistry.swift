import ACCore
import AppKit

/// App-wide duplicate-open guard (`ROADMAP.md` D6/T6.1, `CLAUDE.md`'s
/// "Document & Window Model"): a given `Project` is editable from at most
/// one window at any time. Constructed once in `AutoCueApp`, alongside
/// `DependencyContainer` — not per-window like `AppState`.
///
/// Each Project window registers its `Project.ID` on appear and unregisters
/// on close (via `ProjectWindowView`'s `WindowAccessor`), so this always
/// reflects reality. Before opening a Project window, the caller checks
/// `isOpen(_:)`; if already open, `focus(_:)` brings the existing window to
/// front via `NSWindow.makeKeyAndOrderFront` — the AppKit-interop escape
/// hatch `CLAUDE.md`'s Technology Stack table allows for "when SwiftUI has a
/// genuine gap": bringing an existing `WindowGroup(for:)` window to front by
/// its data identity isn't directly exposed by SwiftUI as of this writing.
@MainActor
final class OpenProjectWindowRegistry {
    private var openWindows: [Project.ID: NSWindow] = [:]

    /// The Library scene's own window, tracked the same way — not because
    /// it's a `Project`, but because it needs the identical "is one already
    /// open? focus it instead of opening a second one" guard: the Library
    /// is a true singleton (`CLAUDE.md`, "Document & Window Model"), and
    /// `WindowGroup(id:)` alone doesn't guarantee that — `openWindow(id:)`
    /// happily opens a second window if called while one already exists.
    private var libraryWindow: NSWindow?

    func isOpen(_ id: Project.ID) -> Bool {
        openWindows[id] != nil
    }

    func register(_ id: Project.ID, window: NSWindow) {
        openWindows[id] = window
    }

    func unregister(_ id: Project.ID) {
        openWindows.removeValue(forKey: id)
    }

    func focus(_ id: Project.ID) {
        openWindows[id]?.makeKeyAndOrderFront(nil)
    }

    func isLibraryWindowOpen() -> Bool {
        libraryWindow != nil
    }

    func registerLibraryWindow(_ window: NSWindow) {
        libraryWindow = window
    }

    func unregisterLibraryWindow() {
        libraryWindow = nil
    }

    func focusLibraryWindow() {
        libraryWindow?.makeKeyAndOrderFront(nil)
    }
}
