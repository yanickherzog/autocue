import ACCore
import ACDesignSystem
import SwiftUI

/// The Library scene's root content (`ROADMAP.md` D6/T6.2, `CLAUDE.md`'s
/// "Document & Window Model"). Receives its `ViewModel` as a plain
/// initializer parameter, per `CLAUDE.md`'s Dependency Injection Pattern —
/// never constructs or looks one up itself. Opening a Project window is not
/// this View's job either: `onOpenProject` is supplied by the App target's
/// scene root, which is the only place with access to `openWindow`/
/// `OpenProjectWindowRegistry` — the same adapter-at-the-edge pattern
/// `WaveformView`/`CueTableView` already establish for crossing a package
/// boundary via a plain closure instead of a type this package can't depend on.
public struct ProjectLibraryView: View {
    @Bindable private var viewModel: ProjectLibraryViewModel
    private let onOpenProject: (Project.ID) -> Void

    @State private var isShowingNewProjectSheet = false
    @State private var newProjectName = ""

    public init(viewModel: ProjectLibraryViewModel, onOpenProject: @escaping (Project.ID) -> Void) {
        _viewModel = Bindable(viewModel)
        self.onOpenProject = onOpenProject
    }

    public var body: some View {
        Group {
            if viewModel.projects.isEmpty {
                EmptyStateView(
                    systemImage: "folder",
                    title: "No Projects Yet",
                    message: "Create a project to get started.",
                    actionTitle: "New Project",
                    surface: .primary,
                    action: { isShowingNewProjectSheet = true }
                )
            } else {
                List {
                    ForEach(viewModel.projects) { project in
                        ProjectRow(
                            project: project,
                            onOpen: { onOpenProject(project.id) },
                            onDelete: { Task { await viewModel.deleteProject(id: project.id) } }
                        )
                        .listRowBackground(Theme.Surface.primary.background)
                    }
                }
                .listStyle(.plain)
                // List/ScrollView on macOS paint their own native background
                // material (dark under system Dark Mode) behind rows by
                // default — a plain `.background()` on the List does not
                // override it. `.scrollContentBackground(.hidden)` suppresses
                // that native chrome so the explicit Theme background (below
                // and per-row above) is what actually shows, matching this
                // app's fixed, non-adaptive palette (CLAUDE.md, "Visual
                // Language") instead of a system-appearance-dependent one.
                .scrollContentBackground(.hidden)
                .background(Theme.Surface.primary.background)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .background(Theme.Surface.primary.background)
        .toolbar {
            ToolbarItem {
                Button("New Project") { isShowingNewProjectSheet = true }
                    .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: .primary))
            }
        }
        .sheet(isPresented: $isShowingNewProjectSheet) {
            NewProjectSheet(
                name: $newProjectName,
                onCreate: {
                    let name = newProjectName
                    newProjectName = ""
                    isShowingNewProjectSheet = false
                    Task { await viewModel.createProject(name: name) }
                },
                onCancel: {
                    newProjectName = ""
                    isShowingNewProjectSheet = false
                }
            )
        }
        .errorAlert(message: $viewModel.errorMessage)
        .task { viewModel.startObserving() }
    }
}

private struct NewProjectSheet: View {
    @Binding var name: String
    let onCreate: () -> Void
    let onCancel: () -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("New Project")
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.primary.foreground)

            // Explicit foregroundStyle: TextField otherwise falls back to
            // the system's dynamic label color, which resolves near-white
            // under system Dark Mode regardless of this app's own fixed
            // white surface background — invisible text, not just a
            // stylistic miss. The `prompt:` variant lets the placeholder use
            // the documented ghost-text token (CLAUDE.md, "Visual Language")
            // instead of the system's default placeholder gray.
            TextField("", text: $name, prompt: Text("Project Name").foregroundStyle(Theme.Colors.ghostTextPrimary))
                .foregroundStyle(Theme.Surface.primary.foreground)
                .textFieldStyle(.plain)
                .padding(Theme.Spacing.sm)
                .overlay(Rectangle().strokeBorder(Theme.Colors.carbonBlack.opacity(0.3), lineWidth: 1))
                .onSubmit(onCreate)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                Button("Create", action: onCreate)
                    .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: .primary))
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 320)
        .background(Theme.Surface.primary.background)
    }
}
