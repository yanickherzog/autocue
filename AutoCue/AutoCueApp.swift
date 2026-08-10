import ACCore
import ACDesignSystem
import SwiftUI

/// Thin composition root (`ROADMAP.md` D6/T6.1). Declares the three scenes
/// `CLAUDE.md`'s "Document & Window Model" specifies: a singleton Library
/// scene, a `WindowGroup(for: Project.ID.self)` Project-window scene, and
/// the standard `Settings` scene. `DependencyContainer` and
/// `OpenProjectWindowRegistry` are each constructed exactly once here, at
/// launch — the same "instantiated once" tier, but `DependencyContainer`
/// wires services and `OpenProjectWindowRegistry` tracks window state; they
/// are deliberately separate types, not combined into one.
@main
struct AutoCueApp: App {
    private let container = DependencyContainer()
    private let registry = OpenProjectWindowRegistry()

    /// Read directly on `App`, not a View — `.commands { }` is built outside
    /// any View's body, so this is the supported way to reach `openWindow`
    /// from a menu command.
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Explicit `id`: needed to target this specific WindowGroup with
        // `openWindow(id:)` from the "New Project" command below.
        WindowGroup(id: "library") {
            LibraryWindowView(container: container, registry: registry)
        }
        .commands {
            // The Library is a singleton (CLAUDE.md, "Document & Window
            // Model") — stock WindowGroup allows ⌘N to open a duplicate by
            // default, so the standard "New Window" command is replaced,
            // not just removed. Found missing entirely during D6's manual
            // verification: with no replacement, closing or losing track of
            // the Library window left no way back to it short of quitting
            // and relaunching — a real gap in D6's own scope (creating/
            // opening a second project requires reaching the Library),
            // not cosmetic. Same duplicate-open guard as Project windows:
            // focus the existing Library window if one's open, otherwise
            // reopen it — never blindly call `openWindow` again, which
            // would spawn a second Library window.
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    if registry.isLibraryWindowOpen() {
                        registry.focusLibraryWindow()
                    } else {
                        openWindow(id: "library")
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        WindowGroup(for: Project.ID.self) { projectIDBinding in
            if let projectID = projectIDBinding.wrappedValue {
                ProjectWindowView(projectID: projectID, registry: registry)
            }
        }
        .defaultSize(Theme.Layout.defaultWindowSize)

        Settings {
            // App-level, project-unscoped (SPEC.md §4.7) — entirely outside
            // the Project-window navigation hierarchy (CLAUDE.md,
            // "Navigation Model"). Real content is ROADMAP.md D14/T14.2.
            EmptyStateView(
                systemImage: "gearshape",
                title: "Settings",
                message: "Coming in ROADMAP.md D14."
            )
            .frame(width: 420, height: 240)
        }
    }
}
