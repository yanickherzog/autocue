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
                    actionTitle: "New Cue Sheet",
                    surface: .primary,
                    action: { isShowingNewProjectSheet = true }
                )
            } else {
                List {
                    // A single List row containing every project, not one
                    // List row per project. Measured, not assumed: an
                    // earlier version gave each project its own List row
                    // with a trailing divider, and a real pixel measurement
                    // (window-scoped screenshot, PIL) showed the gap above
                    // each divider was consistently ~27px while the gap
                    // below was ~43px, at 2x scale — an extra 8pt
                    // (Theme.Spacing.sm) appearing only below the divider.
                    // The reason: the "above" gap was entirely inside one
                    // List row's own VStack, while the "below" gap crossed
                    // a genuine List row boundary — and macOS's `List`
                    // applies its own default inter-row spacing there that
                    // `.listRowSpacing` can't zero out (it's iOS/watchOS/
                    // tvOS-only — confirmed by a real build error, not
                    // assumed). Collapsing everything into one List row
                    // means every gap, including the ones around each
                    // divider, is governed purely by this VStack's own
                    // explicit padding, with no List-native row boundary
                    // left anywhere in the middle to add uncontrolled space
                    // to only one side.
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.projects.enumerated()), id: \.element.id) { index, project in
                            if index == 0 {
                                // List-level top inset (matches the row's
                                // own .horizontal padding below, so the top
                                // of the list feels as inset as its
                                // left/right edges) — a different concern
                                // from the symmetric inter-row gap the
                                // divider owns, kept separate for the same
                                // reason as before.
                                Color.clear.frame(height: Theme.Spacing.md)
                            }
                            ProjectRow(
                                project: project,
                                onOpen: { onOpenProject(project.id) },
                                onDelete: { Task { await viewModel.deleteProject(id: project.id) } }
                            )
                            // A simple straight line between projects, per
                            // CLAUDE.md's Visual Language ("Dividers: simple
                            // straight lines... colored from Theme.Colors
                            // rather than the system default gray") —
                            // stock Divider() re-tinted via .overlay, the
                            // same convention as every other divider this
                            // app uses, not a new component. Only between
                            // rows, not trailing the last one.
                            if index < viewModel.projects.count - 1 {
                                Divider()
                                    .overlay(Theme.Colors.dividerPrimary)
                                    // .horizontal matches ProjectRow's own
                                    // horizontal padding exactly, so the
                                    // divider's ends line up with the row
                                    // content's left/right edges. .vertical
                                    // is a single value applied to both top
                                    // and bottom in one call; combined with
                                    // ProjectRow's own symmetric .xs padding
                                    // (equal on both of its sides) and no
                                    // List row boundary anywhere nearby, the
                                    // total gap on each side of the divider
                                    // is provably the same amount.
                                    .padding(.horizontal, Theme.Spacing.md)
                                    .padding(.vertical, Theme.Spacing.sm)
                            }
                        }
                    }
                    .listRowBackground(Theme.Surface.primary.background)
                    .listRowSeparator(.hidden)
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
                Button("New Cue Sheet") { isShowingNewProjectSheet = true }
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
            Text("New Cue Sheet")
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
