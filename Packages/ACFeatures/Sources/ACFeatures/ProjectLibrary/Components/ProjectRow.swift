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
            // spacing: 0, not a Theme.Spacing token — Theme.Spacing's
            // smallest value (.xs, 4pt) still read as too far apart between
            // a title and its own date (manual verification follow-up);
            // 0 here means "no additional gap beyond the font's own
            // leading," a structural choice, not a stylistic one, so it's
            // not a "magic number" in the sense CLAUDE.md's token rule
            // means to prevent — the same reasoning already applied to the
            // Divider-wrapping VStack in ProjectLibraryView.
            VStack(alignment: .leading, spacing: 0) {
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
        // Horizontal padding on the whole row container (not the title
        // text alone) — an earlier version of this padded only the leading
        // edge in front of the title, which nudged the text right while
        // the trailing Open/Delete buttons stayed flush against the
        // window's edge. Applying it to the row's full HStack insets
        // everything — text and buttons alike — equally from both edges.
        //
        // Vertical padding is deliberately symmetric — one .xs value, both
        // sides — not split into a larger top and smaller bottom. An
        // earlier version gave top Theme.Spacing.md and bottom .xs (to make
        // the row's own top edge feel as inset as its left/right), but that
        // made the divider that follows each row sit visibly off-center:
        // its gap to the row above it was only .xs, while its gap to the
        // next row's content was .md, because each row's own top/bottom
        // independently contributed a different amount (manual verification
        // follow-up). The row's own top-inset need is met a different way
        // now — ProjectLibraryView adds it once, only above the first row —
        // so every row's own padding can stay simple and symmetric, and
        // divider centering (also ProjectLibraryView's job, via the
        // divider's own single symmetric .padding(.vertical, sm) call) isn't
        // fighting an asymmetric contribution from here.
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
        // Per CLAUDE.md's Document & Window Model: "Selecting or
        // double-clicking a project here opens (or focuses) that project's
        // window." The explicit "Open" button above covers the same action
        // for discoverability; this covers the documented interaction.
        .onTapGesture(count: 2, perform: onOpen)
    }
}
