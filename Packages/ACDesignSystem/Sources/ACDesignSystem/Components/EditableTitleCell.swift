import SwiftUI

/// The Cue Title column's cell — a real `TextField`, backed by local
/// `@State` seeded from `row.title` so keystrokes render immediately
/// without waiting on a round-trip through the caller's debounced save
/// (`ROADMAP.md` D10/T10.2, SPEC.md §4.18). A dedicated child view, not an
/// inline closure, specifically so this `@State` survives `Table`'s own
/// re-diffing of the row closure across re-renders — SwiftUI keys per-row
/// identity by `CueTableRow.id`, so this cell's local text stays put across
/// unrelated state changes (e.g. another row's edit, playback ticking) as
/// long as this row's `id` doesn't change.
///
/// Also renders the small validation-warning glyph (`row.hasValidationIssue`)
/// leading the field — a non-blocking indicator only (SPEC.md §4.6): a cue's
/// shares can be left non-100% at edit time, this just makes that visible
/// per-row without stopping anything.
///
/// Not `private`: split into its own file (from `CueTableView.swift`) to
/// stay under this project's file-length lint limit — `private` is
/// file-scoped in Swift, so `CueTableView`'s own `body` needs this visible
/// at `internal` (the default), not the app-wide `public` API.
struct EditableTitleCell: View {
    let row: CueTableRow
    var focusedTitleRowID: FocusState<Int?>.Binding
    let onTitleChanged: (Int, String) -> Void

    @State private var text: String

    init(
        row: CueTableRow,
        focusedTitleRowID: FocusState<Int?>.Binding,
        onTitleChanged: @escaping (Int, String) -> Void
    ) {
        self.row = row
        self.focusedTitleRowID = focusedTitleRowID
        self.onTitleChanged = onTitleChanged
        _text = State(initialValue: row.title)
    }

    var body: some View {
        HStack(spacing: 4) {
            if row.hasValidationIssue {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityLabel(Text("Right-holder shares don't sum to 100% for cue \(row.number)"))
            }
            TextField(
                "",
                text: $text,
                prompt: Text("Untitled").foregroundStyle(Theme.Colors.ghostTextPrimary)
            )
            .textFieldStyle(.plain)
            .font(Theme.Typography.font(.regular, size: 12))
            // White, not `Theme.Surface.primary.foreground` (Carbon Black) —
            // found during real manual testing: this `Table`'s row
            // background renders dark (a native `NSTableView` appearance
            // leak that follows the system's actual Light/Dark Mode setting,
            // independent of this screen's own hardcoded white
            // `Theme.Surface.primary` background elsewhere), so Carbon Black
            // text here was nearly unreadable rather than merely
            // low-contrast. White stays legible against that real row
            // background regardless of the system appearance; fixing the
            // underlying leak so `Table` itself always renders light,
            // matching `CLAUDE.md`'s "AutoCue does not adapt to system
            // Light/Dark Mode," is a separate, broader follow-up (`Table` is
            // this project's one real AppKit-interop gap, `CLAUDE.md`'s
            // Technology Stack table), not scoped to this fix.
            .foregroundStyle(Theme.Colors.white)
            .tint(Theme.Colors.white.opacity(0.3))
            .focused(focusedTitleRowID, equals: row.id)
            // An external update (a fresh live-stream emission after this
            // row's own debounced save lands, or an unrelated edit from
            // another window) may hand this cell a new `row` value with a
            // different `title` — resync local state only when it actually
            // differs, so this never clobbers a keystroke the user is
            // mid-typing when the two happen to coincide.
            .onChange(of: row.title) { _, newValue in
                if newValue != text {
                    text = newValue
                }
            }
            .onChange(of: text) { _, newValue in onTitleChanged(row.id, newValue) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
