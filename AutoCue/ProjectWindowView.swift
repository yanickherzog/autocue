import ACCore
import ACDesignSystem
import ACFeatures
import SwiftUI

/// Root content of one Project window (`ROADMAP.md` D6/T6.1) — the 2-column
/// `NavigationSplitView` shell `CLAUDE.md`'s "Navigation Model" describes:
/// content = the three always-accessible section tabs, detail = the active
/// screen. Real screen content (`SetupView`, `CueSheetEditorView`,
/// `ReviewAndExportView`) doesn't exist until D7/D9–D10/D11 — each tab shows
/// a plain `EmptyStateView` placeholder until then, per D6's own scope.
///
/// Owns this window's `AppState` (`ACFeatures`) — constructed once per
/// window via `@State`, never a single app-wide instance (`CLAUDE.md`,
/// "Document & Window Model"). Registers/unregisters this window's
/// `Project.ID` with `OpenProjectWindowRegistry` on appear/disappear via
/// `WindowAccessor`, so the registry always reflects which Projects are
/// actually open.
struct ProjectWindowView: View {
    let projectID: Project.ID
    let registry: OpenProjectWindowRegistry

    @State private var appState = AppState()
    /// Retains the observer for this window's lifetime — see
    /// `ProjectWindowFrameSaver`'s doc comment for why this can't just be a
    /// local variable in the closure below.
    @State private var frameSaver: ProjectWindowFrameSaver?

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
            EmptyStateView(
                systemImage: "doc.text",
                title: "Setup",
                message: "Coming in ROADMAP.md D7.",
                surface: .primary
            )
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
