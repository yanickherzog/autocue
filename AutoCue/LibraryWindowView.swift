import ACCore
import ACFeatures
import SwiftUI

/// Root content of the singleton Library scene (`ROADMAP.md` D6/T6.1–T6.2).
/// The only call site that invokes `DependencyContainer.makeProjectLibraryViewModel()`
/// — the ViewModel is created once (via `@State`, not recomputed on every
/// `body` re-evaluation) and handed to `ProjectLibraryView` as a plain
/// initializer parameter, per `CLAUDE.md`'s Dependency Injection Pattern.
///
/// Also the only place that decides how "open this project" actually
/// behaves — `ProjectLibraryView` (`ACFeatures`) has no access to
/// `openWindow`/`OpenProjectWindowRegistry`, both App-target/AppKit
/// concerns; it only calls the `onOpenProject` closure supplied here.
struct LibraryWindowView: View {
    let container: DependencyContainer
    let registry: OpenProjectWindowRegistry

    @Environment(\.openWindow) private var openWindow
    @State private var viewModel: ProjectLibraryViewModel

    init(container: DependencyContainer, registry: OpenProjectWindowRegistry) {
        self.container = container
        self.registry = registry
        _viewModel = State(initialValue: container.makeProjectLibraryViewModel())
    }

    var body: some View {
        ProjectLibraryView(viewModel: viewModel) { projectID in
            // Duplicate-open prevention (CLAUDE.md, "Document & Window
            // Model"): focus the existing window instead of opening a
            // second one for the same Project.
            if registry.isOpen(projectID) {
                registry.focus(projectID)
            } else {
                openWindow(value: projectID)
            }
        }
    }
}
