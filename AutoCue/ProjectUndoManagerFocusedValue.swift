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
/// above.** `ProjectWindowView` publishes its own `UndoManager` via
/// `.focusedSceneValue(\.projectUndoManager, undoManager)`; `AutoCueApp`'s
/// `CommandGroup(replacing: .undoRedo)` reads it back via
/// `@FocusedValue(\.projectUndoManager)` to build real Undo/Redo menu items
/// (⌘Z/⌘⇧Z) that call directly into whichever Project window currently has
/// focus. `CueDetectionReviewView`'s own need for the same instance (to
/// pass into `CueDetectionReviewViewModel.deleteCue`) is unrelated to this
/// file — that's a plain `init` parameter, the same as `viewModel`, not
/// routed through `FocusedValues` at all.
private struct ProjectUndoManagerFocusedValueKey: FocusedValueKey {
    typealias Value = UndoManager
}

extension FocusedValues {
    var projectUndoManager: UndoManager? {
        get { self[ProjectUndoManagerFocusedValueKey.self] }
        set { self[ProjectUndoManagerFocusedValueKey.self] = newValue }
    }
}

/// The Edit-menu Undo/Redo items themselves — a tiny View (not inline in
/// `AutoCueApp`'s `.commands` closure) purely so `@FocusedValue` has a
/// `body` to be evaluated in; `CommandGroup`'s own content closure isn't a
/// View context that property wrapper can be read from directly.
struct ProjectUndoRedoCommands: View {
    @FocusedValue(\.projectUndoManager) private var undoManager

    var body: some View {
        Button("Undo") {
            undoManager?.undo()
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(undoManager?.canUndo != true)

        Button("Redo") {
            undoManager?.redo()
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(undoManager?.canRedo != true)
    }
}
