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
    @State private var searchQuery = ""
    @FocusState private var isSearchFieldFocused: Bool

    public init(viewModel: ProjectLibraryViewModel, onOpenProject: @escaping (Project.ID) -> Void) {
        _viewModel = Bindable(viewModel)
        self.onOpenProject = onOpenProject
    }

    /// Search by cue sheet (Project) name — case-insensitive substring match,
    /// live-filtered as the user types. View-local, not `ProjectLibraryViewModel`
    /// state: this is display-only filtering with no persistence or side effect,
    /// the same category of thing `isShowingNewProjectSheet`/`newProjectName`
    /// already are on this View, not a business rule that belongs in a Use Case.
    private var filteredProjects: [Project] {
        guard !searchQuery.isEmpty else { return viewModel.projects }
        return viewModel.projects.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    public var body: some View {
        Group {
            if filteredProjects.isEmpty {
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
                    // Real projects exist, just none matching the current
                    // search — a distinct state from "no projects yet," so it
                    // gets its own message with no "create new" action
                    // (there's nothing wrong with the library, only the
                    // search term).
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: "No Matches",
                        message: "No cue sheets match your search.",
                        surface: .primary
                    )
                }
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
                        ForEach(Array(filteredProjects.enumerated()), id: \.element.id) { index, project in
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
                            if index < filteredProjects.count - 1 {
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
        // .safeAreaInset, not manual bottom padding/frame math on the List —
        // this automatically insets the scrollable content area to make room
        // for the search bar, so overlap between the two is prevented by
        // construction (the list literally cannot lay out content underneath
        // the inset), not by a magic-number bottom padding that could later
        // drift out of sync with the search bar's actual height. Attached to
        // the Group (both the empty-state and List branches), not just the
        // List, so the search bar stays permanently visible regardless of
        // which branch is showing.
        .safeAreaInset(edge: .bottom) {
            searchBar
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

    /// Bottom-anchored, permanently visible — never a collapsible/toggled
    /// search field. The magnifying-glass icon is clickable too (not purely
    /// decorative): tapping it focuses the text field via `@FocusState`, the
    /// same as tapping the field itself already does natively.
    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
                .onTapGesture { isSearchFieldFocused = true }
                .pointingHandCursor()
            TextField(
                "",
                text: $searchQuery,
                prompt: Text("Search cue sheets").foregroundStyle(Theme.Colors.ghostTextPrimary)
            )
            .foregroundStyle(Theme.Surface.primary.foreground)
            .textFieldStyle(.plain)
            .focused($isSearchFieldFocused)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Surface.primary.background)
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
