import ACCore
import ACDesignSystem
import SwiftUI

/// One row in `ProjectLibraryView`. Stays in `ACFeatures` rather than
/// `ACDesignSystem` — it needs `ACCore.Project` to make sense at all, which
/// disqualifies it from the design system per `CLAUDE.md`'s Reusable
/// Component Philosophy ("if it needs a domain type to make sense, it stays
/// in `ACFeatures`").
struct ProjectRow: View {
    let project: Project
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(project.name)
                    .font(Theme.Typography.font(.medium, size: 15))
                    .foregroundStyle(Theme.Surface.primary.foreground)
                Text(project.updatedAt, style: .date)
                    .font(Theme.Typography.font(.regular, size: 12))
                    .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
            }

            Spacer()

            Button("Open", action: onOpen)
                .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: .primary))
            Button("Delete", action: onDelete)
                .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
        // Per CLAUDE.md's Document & Window Model: "Selecting or
        // double-clicking a project here opens (or focuses) that project's
        // window." The explicit "Open" button above covers the same action
        // for discoverability; this covers the documented interaction.
        .onTapGesture(count: 2, perform: onOpen)
    }
}
