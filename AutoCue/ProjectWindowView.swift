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

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .background(
            WindowAccessor { window in
                registry.register(projectID, window: window)
            }
        )
        .onDisappear {
            registry.unregister(projectID)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            sidebarButton(.setup, title: "Setup")
            sidebarButton(.cueSheet, title: "Cue Sheet")
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
                title: "Cue Sheet",
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
