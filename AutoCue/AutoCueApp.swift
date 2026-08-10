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

    var body: some Scene {
        WindowGroup {
            LibraryWindowView(container: container, registry: registry)
        }
        .commands {
            // The Library is a singleton (CLAUDE.md, "Document & Window
            // Model") — stock WindowGroup allows ⌘N to open a duplicate by
            // default, so the standard "New Window" command is removed
            // entirely rather than left to accidentally violate that.
            CommandGroup(replacing: .newItem) {}
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
