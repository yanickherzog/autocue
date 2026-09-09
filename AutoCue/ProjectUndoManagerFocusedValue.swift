import SwiftUI

/// **Why not `\.undoManager`:** SwiftUI's own built-in `EnvironmentValues.undoManager`
/// is `{ get }`-only — confirmed at compile time (`WritableKeyPath` vs.
/// `KeyPath` mismatch), not assumed — because it exists to *read* whatever
/// `UndoManager` a `DocumentGroup`/`NSDocument` scene already supplied via
/// the real AppKit responder chain, not to let an arbitrary `WindowGroup`
/// scene *supply* one. This app deliberately doesn't use `DocumentGroup`
/// (`CLAUDE.md`, "Document & Window Model"), so that key is always `nil`
/// here regardless of what this file does.
///
/// **Why not `NSWindowDelegate.windowWillReturnUndoManager(_:)` either:**
/// that's the other standard AppKit hook for a custom per-window
/// `UndoManager`, but it requires becoming `window.delegate` — a single
/// slot this project has already deliberately avoided claiming once before
/// (`ProjectWindowFrameSaver`'s own doc comment: SwiftUI's `WindowGroup(for:)`
/// may already be using it internally, and overwriting it wholesale risks
/// silently breaking window restoration/fullscreen/tabbing behavior this
/// project has no way to fully audit).
///
/// **The actual mechanism: `FocusedValues`, SwiftUI's supported way to let
/// per-window state reach App-level `.commands` without either of the
/// above.** `ProjectWindowView` publishes a `ProjectUndoManagerObserver`
/// (below) via `.focusedSceneValue(\.projectUndoManager, observer)`;
/// `AutoCueApp`'s `CommandGroup(replacing: .undoRedo)` reads it back via
/// `@FocusedValue(\.projectUndoManager)` to build real Undo/Redo menu items
/// (⌘Z/⌘⇧Z) that call directly into whichever Project window currently has
/// focus. `CueDetectionReviewView`'s own need for the raw `UndoManager` (to
/// pass into `CueDetectionReviewViewModel.deleteCue`) is unrelated to this
/// file — that's a plain `init` parameter, the same as `viewModel`, not
/// routed through `FocusedValues` at all.
///
/// **Why `ProjectUndoManagerObserver` exists at all, instead of publishing
/// the raw `UndoManager` directly (what this file originally did) — found
/// via a real, reproduced bug, not anticipated in advance.** Manual testing
/// found ⌘Z doing nothing immediately after a cue delete, while working
/// correctly the moment the app was switched away from and back. Real
/// diagnostic logging (not a guess) proved this was never a keyboard-focus/
/// first-responder problem — `CueDetectionReviewView`'s own `isFocused`
/// never changed across the delete at all. The real cause: `UndoManager` is
/// a plain `NSObject`, not `@Observable`/`ObservableObject`. `registerUndo`
/// (`CueDetectionReviewViewModel+Delete.swift`) genuinely, synchronously
/// flips the real manager's `canUndo` to `true` the instant a cue is
/// deleted — that part of the mechanism was never broken. But
/// `@FocusedValue` only re-evaluates its reader's `body` when the *focused
/// scene binding itself* changes (a new focused window/scene), never merely
/// because the object it hands back mutated internal state on its own — so
/// `ProjectUndoRedoCommands.body`, and therefore the `.disabled(...)` gate
/// ⌘Z's routing depends on, kept reading a stale snapshot from whenever
/// focus was last (re)established, until an app switch forced SwiftUI to
/// recompute focus and read it fresh. Confirmed directly in a real captured
/// log: `canUndo` read `false` for several seconds after a delete that had
/// already set the real manager's `canUndo` to `true`, only flipping to
/// `true` in the log the moment the window regained key status after an
/// app switch. `ProjectUndoManagerObserver` fixes this at the actual root
/// — it mirrors `UndoManager`'s `canUndo`/`canRedo` into `@Observable`
/// properties, kept in sync via the real notifications `UndoManager` itself
/// posts around every state change, so SwiftUI's Observation system
/// invalidates `ProjectUndoRedoCommands.body` when those values genuinely
/// change — not only when focus happens to change. See `docs/DECISIONS.md`.
@Observable
final class ProjectUndoManagerObserver {
    let undoManager: UndoManager
    private(set) var canUndo: Bool
    private(set) var canRedo: Bool

    private var tokens: [NSObjectProtocol] = []

    init(undoManager: UndoManager) {
        self.undoManager = undoManager
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
        tokens = Self.observedNotificationNames.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: undoManager,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    deinit {
        let center = NotificationCenter.default
        tokens.forEach { center.removeObserver($0) }
    }

    /// `registerUndo` implicitly opens/closes an undo group, and both
    /// `undo()`/`redo()` change the stacks directly — observing all four of
    /// `UndoManager`'s own state-change notifications, rather than reasoning
    /// precisely about which single one covers `registerUndo` specifically,
    /// keeps this robust without depending on undocumented notification-
    /// timing behavior.
    private static let observedNotificationNames: [Notification.Name] = [
        .NSUndoManagerCheckpoint,
        .NSUndoManagerDidUndoChange,
        .NSUndoManagerDidRedoChange,
        .NSUndoManagerDidCloseUndoGroup,
    ]

    private func refresh() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }
}

private struct ProjectUndoManagerFocusedValueKey: FocusedValueKey {
    typealias Value = ProjectUndoManagerObserver
}

extension FocusedValues {
    var projectUndoManager: ProjectUndoManagerObserver? {
        get { self[ProjectUndoManagerFocusedValueKey.self] }
        set { self[ProjectUndoManagerFocusedValueKey.self] = newValue }
    }
}

/// The Edit-menu Undo/Redo items themselves — a tiny View (not inline in
/// `AutoCueApp`'s `.commands` closure) purely so `@FocusedValue` has a
/// `body` to be evaluated in; `CommandGroup`'s own content closure isn't a
/// View context that property wrapper can be read from directly.
struct ProjectUndoRedoCommands: View {
    @FocusedValue(\.projectUndoManager) private var observer

    var body: some View {
        Button("Undo") {
            observer?.undoManager.undo()
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(observer?.canUndo != true)

        Button("Redo") {
            observer?.undoManager.redo()
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(observer?.canRedo != true)
    }
}
