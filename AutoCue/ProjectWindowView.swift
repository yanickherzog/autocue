import ACCore
import ACDesignSystem
import ACFeatures
import SwiftUI

/// Root content of one Project window (`ROADMAP.md` D6/T6.1) — the 2-column
/// `NavigationSplitView` shell `CLAUDE.md`'s "Navigation Model" describes:
/// content = the three always-accessible section tabs, detail = the active
/// screen. `SetupView` is real as of `ROADMAP.md` D7; `CueSheetEditorView`/
/// `ReviewAndExportView` still show a placeholder `EmptyStateView` until
/// D9–D10/D11.
///
/// Owns this window's `AppState` (`ACFeatures`) — constructed once per
/// window via `@State`, never a single app-wide instance (`CLAUDE.md`,
/// "Document & Window Model"). Registers/unregisters this window's
/// `Project.ID` with `OpenProjectWindowRegistry` on appear/disappear via
/// `WindowAccessor`, so the registry always reflects which Projects are
/// actually open.
///
/// `init` is the only call site that invokes
/// `DependencyContainer.makeSetupViewModel(for:)`/
/// `.makeRightHolderDirectoryViewModel(for:)`, per `CLAUDE.md`'s Dependency
/// Injection Pattern — `SetupView` itself never sees `container`.
///
/// **`setupViewModel`/`rightHolderDirectoryViewModel` are constructed
/// exactly once, in `init`, and held via `@State` for the whole window's
/// lifetime — not reconstructed inside `detail`.** `detail` was originally a
/// plain computed property that called `container.makeSetupViewModel(for:)`
/// directly inside its `.setup` case — computed properties re-run their
/// entire body on every access, and SwiftUI can re-evaluate `body` (and
/// therefore `detail`) for reasons well beyond an explicit tab switch. Every
/// re-evaluation was silently minting a **brand-new** `SetupViewModel` with
/// `hasLoadedInitialSetup = false` and empty `people`/`labels` — from the
/// user's perspective this looked exactly like "everything just vanished,"
/// because it had: the View was pointed at a fresh, not-yet-loaded object,
/// not the one holding their actual edits. This also meant any pending
/// *debounced* save was at real risk: `SetupViewModel.updateDebounced`'s
/// scheduled `Task` captures `[weak self]`, so if the *only* strong
/// reference to that specific `SetupViewModel` instance (the old, discarded
/// `SetupView`) went away before the 500ms debounce fired, the save was
/// silently dropped. Constructing these once, here, and never again for the
/// life of the window removes the entire class of bug — `SetupView` itself
/// can still be freely reconstructed by SwiftUI (its own local `draft`
/// mirror may reset), but it always re-seeds from the *same*, already-loaded
/// `viewModel.setup`, never a fresh placeholder.
struct ProjectWindowView: View {
    let projectID: Project.ID
    let registry: OpenProjectWindowRegistry
    let container: DependencyContainer

    @State private var appState = AppState()
    /// Retains the observer for this window's lifetime — see
    /// `ProjectWindowFrameSaver`'s doc comment for why this can't just be a
    /// local variable in the closure below.
    @State private var frameSaver: ProjectWindowFrameSaver?
    /// See `ProjectWindowFrameSaver`'s doc comment — same reasoning, same
    /// `NSWindow.willCloseNotification` mechanism, applied to flushing a
    /// pending debounced Setup save instead of the window frame. Needed
    /// because SwiftUI's `.onDisappear` is not reliably triggered by a real
    /// window close in this `WindowGroup(for:)` context — confirmed by this
    /// exact finding already being the reason `ProjectWindowFrameSaver`
    /// exists at all, not a new assumption made here.
    @State private var saveFlusher: ProjectWindowSaveFlusher?

    // @State, deliberately, not plain `let` — a View `struct`'s `init` reruns
    // on every SwiftUI reconstruction of it (which happens on every
    // re-render), so a plain `let` initialized from `container.make...(for:)`
    // would reconstruct a fresh ViewModel just as often as the original
    // `detail`-computed-property bug did, only relocated. `@State`'s
    // `initialValue:` expression is guaranteed by SwiftUI to run only once,
    // the first time this view's identity is created — every subsequent
    // `init` call for the *same* identity reuses the already-stored value.
    @State private var setupViewModel: SetupViewModel
    @State private var rightHolderDirectoryViewModel: RightHolderDirectoryViewModel

    init(projectID: Project.ID, registry: OpenProjectWindowRegistry, container: DependencyContainer) {
        self.projectID = projectID
        self.registry = registry
        self.container = container
        _setupViewModel = State(initialValue: container.makeSetupViewModel(for: projectID))
        _rightHolderDirectoryViewModel = State(initialValue: container
            .makeRightHolderDirectoryViewModel(for: projectID))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .background(
            WindowAccessor { window in
                registry.register(projectID, window: window)
                // Per-Project window-size persistence (ROADMAP.md D6,
                // manual verification follow-up). Explicit, not
                // `NSWindow.setFrameAutosaveName` — that was tried first and
                // confirmed, via `defaults read com.autocue.AutoCue`, to
                // never actually persist anything in this SwiftUI
                // `WindowGroup(for:)` context (see `ProjectWindowFrameStore`'s
                // doc comment for the full finding). If this Project has a
                // previously saved frame, apply it now; a Project opened for
                // the first time has none, so this is a no-op and the
                // window stays at whatever `Theme.Layout.defaultWindowSize`
                // (`.defaultSize` on the WindowGroup in AutoCueApp.swift)
                // already sized it to.
                if let savedFrame = ProjectWindowFrameStore.savedFrame(for: projectID) {
                    window.setFrame(savedFrame, display: true, animate: false)
                }
                frameSaver = ProjectWindowFrameSaver(window: window, projectID: projectID)
                saveFlusher = ProjectWindowSaveFlusher(window: window, setupViewModel: setupViewModel)
            }
        )
        .onDisappear {
            registry.unregister(projectID)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            sidebarButton(.setup, title: "Setup")
            sidebarButton(.cueSheet, title: "Cues")
            sidebarButton(.reviewAndExport, title: "Review & Export")
            Spacer()
        }
        .padding(Theme.Spacing.sm)
        .frame(minWidth: 160)
        .background(Theme.Surface.primary.background)
    }

    private func sidebarButton(_ section: ProjectSection, title: String) -> some View {
        Button {
            appState.selectedSection = section
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(
            SharpButtonStyle(
                emphasis: appState.selectedSection == section ? .primary : .secondary,
                surface: .primary
            )
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.selectedSection {
        case .setup:
            SetupView(viewModel: setupViewModel, directoryViewModel: rightHolderDirectoryViewModel)
        case .cueSheet:
            EmptyStateView(
                systemImage: "list.bullet.rectangle",
                title: "Cues",
                message: "Coming in ROADMAP.md D9–D10.",
                surface: .primary
            )
        case .reviewAndExport:
            EmptyStateView(
                systemImage: "checkmark.seal",
                title: "Review & Export",
                message: "Coming in ROADMAP.md D11.",
                surface: .reversed
            )
        }
    }
}
