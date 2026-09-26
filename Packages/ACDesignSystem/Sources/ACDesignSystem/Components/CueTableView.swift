import SwiftUI

/// One row's already-formatted display values — never an `ACCore` `Cue`
/// directly, per `CLAUDE.md`'s Design System rule (components take a
/// local, domain-free adapter, same pattern as `WaveformDisplayData`/
/// `WaveformMarker`). All formatting (TC In/TC Out's `HH:MM:SS:FF` via
/// `Setup.timecodeFrameRate`, the nil→"—" placeholder rule, Length's
/// `MM:SS` — SPEC.md §4.3) happens in the `ACFeatures`-layer mapper that
/// produces these, not here.
public struct CueTableRow: Identifiable, Equatable, Sendable {
    /// The row's position in the live `cues` array at the moment this row
    /// was produced — not a stable, persisted identity. Threaded back
    /// through `onRowSelected`/`onDelete` so the caller knows exactly which
    /// cue was clicked/should be removed, the same "plain `Int` index,
    /// never `Cue.ID`" boundary `WaveformMarker` already established.
    public let id: Int
    /// 1-indexed display position ("CUE 1", "CUE 2", …) — always `id + 1`,
    /// but named separately here so this view never has to know that's the
    /// rule; the mapper computes it once.
    public let number: Int
    public let title: String
    public let tcIn: String
    public let tcOut: String
    public let length: String
    /// `true` when `ValidateCueRightHolderSharesUseCase` (`ACCore`) reports
    /// any issue for this cue (`ROADMAP.md` D10/T10.3) — a non-blocking
    /// warning indicator only, per SPEC.md §4.6: a cue's shares can be left
    /// non-100% at edit time, surfaced here, only export-blocking at D11.
    /// Computed by the `ACFeatures`-layer mapper, never here — this view has
    /// no knowledge of `Cue`/`CueRightHolder` to compute it itself.
    public let hasValidationIssue: Bool

    public init(
        id: Int,
        number: Int,
        title: String,
        tcIn: String,
        tcOut: String,
        length: String,
        hasValidationIssue: Bool = false
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.tcIn = tcIn
        self.tcOut = tcOut
        self.length = length
        self.hasValidationIssue = hasValidationIssue
    }
}

/// **Minimal scope, pulled forward from `ROADMAP.md` D10/T10.2** — exactly
/// number/title/TC In/TC Out/Length columns plus the ✕ delete button
/// (SPEC.md §4.18); no "+ Add Cue," no reorder, no `CueRowDetailView`
/// direct-edit, no right-holder editing. `docs/DECISIONS.md` records this
/// pull-forward, per the same test the boundary-marker/split/merge
/// pull-forwards already established: already fully specified in SPEC.md,
/// and scoped to exactly the real caller (`CueDetectionReviewView`) that
/// exists today.
///
/// Cue Sheet section screens use the primary surface (`CLAUDE.md`, "Visual
/// Language") — this view always renders on it, unlike `WaveformView`,
/// which keeps its own reversed background regardless of the surrounding
/// screen.
///
/// **Clicking a row (any column except the play/stop icon and the delete
/// button) plays that cue's span** — `onRowSelected` is wired by the caller
/// directly to the same play-cue-span mechanism a waveform marker click
/// already triggers (`CueDetectionReviewViewModel.playMarkerSpan`), so
/// auditing whether a cue's start is cut off doesn't require finding its
/// marker in the waveform first. The tap gesture is repeated per-column
/// rather than applied once to the row: `Table` has no single whole-row tap
/// target short of its `selection:` binding, which would add persistent
/// system-native row highlighting this view doesn't want.
///
/// **The leading column is a play/stop icon, not the cue number** — a
/// triangle by default, swapping to a square for whichever row's `id`
/// matches `playingRowID`, the same convention `CueDetectionReviewView`'s
/// own toolbar play/stop button already uses (`play.fill`/`stop.fill`).
/// Unlike the rest of the row, this icon toggles both directions —
/// `onPlayToggle` fires on every tap regardless of this row's own state,
/// and it's the caller's job (`CueDetectionReviewViewModel.
/// toggleRowPlayback`) to decide start vs. stop from its own already-known
/// `playingCueID`; this view only ever renders whichever icon
/// `playingRowID` implies, never decides play/stop itself.
///
/// **No reorder UI** — a real ↑/↓ button pair was built and then removed
/// again at the same Deliverable's request: every real cue goes through
/// AutoCue's own detection process (there's no disconnected, position-less
/// manually-added cue to reorder in the first place, per the removal of
/// "+ Add Cue" in the same pass). The underlying `UpdateCueUseCase.reorder`
/// and its ViewModel-level wiring are deliberately left in place, unused,
/// in case a future revision needs them again — see `docs/DECISIONS.md`.
public struct CueTableView: View {
    private let rows: [CueTableRow]
    private let playingRowID: Int?
    private let onRowSelected: (Int) -> Void
    private let onPlayToggle: (Int) -> Void
    private let onTitleChanged: (Int, String) -> Void
    private let onOpenDetail: (Int) -> Void
    private let onDelete: (Int) -> Void
    /// **Found during real manual testing, not anticipated at design time:**
    /// `CueDetectionReviewView`'s existing `.onKeyPress(.space)` (D9,
    /// play/pause) intercepts a space keystroke *before* a focused `TextField`
    /// in this component gets to insert it — confirmed live: typing
    /// "Test Theme" into a newly-added cue's title produced "TestTheme,"
    /// every space silently eaten. Tracking which row's title field (if any)
    /// currently has focus, and reporting that up via this closure, is what
    /// lets the host screen disable that spacebar shortcut while a title is
    /// actually being edited — the fix has to live at this level, since only
    /// this component's own `TextField`s know when they have focus.
    private let onTitleFieldFocusChanged: (Bool) -> Void
    @FocusState private var focusedTitleRowID: Int?

    public init(
        rows: [CueTableRow],
        playingRowID: Int? = nil,
        onRowSelected: @escaping (Int) -> Void = { _ in },
        onPlayToggle: @escaping (Int) -> Void = { _ in },
        onTitleChanged: @escaping (Int, String) -> Void = { _, _ in },
        onOpenDetail: @escaping (Int) -> Void = { _ in },
        onDelete: @escaping (Int) -> Void = { _ in },
        onTitleFieldFocusChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.rows = rows
        self.playingRowID = playingRowID
        self.onRowSelected = onRowSelected
        self.onPlayToggle = onPlayToggle
        self.onTitleChanged = onTitleChanged
        self.onOpenDetail = onOpenDetail
        self.onDelete = onDelete
        self.onTitleFieldFocusChanged = onTitleFieldFocusChanged
    }

    public var body: some View {
        Table(rows) {
            TableColumn("") { row in
                let isPlayingThisRow = row.id == playingRowID
                Button {
                    onPlayToggle(row.id)
                } label: {
                    Image(systemName: isPlayingThisRow ? "stop.fill" : "play.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Colors.white)
                }
                .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                .accessibilityLabel(Text(isPlayingThisRow ? "Stop cue \(row.number)" : "Play cue \(row.number)"))
            }
            .width(32)

            // Editable (`ROADMAP.md` D10/T10.2) — a real `TextField`, not the
            // read-only `Text` this column used through D9's pull-forward.
            // TC In/TC Out/Length below are unaffected: they keep the
            // existing click-plays-span behavior, so typing a title never
            // competes with auditioning a cue's boundaries.
            TableColumn("Title") { row in
                EditableTitleCell(row: row, focusedTitleRowID: $focusedTitleRowID, onTitleChanged: onTitleChanged)
            }

            TableColumn("TC In") { row in
                Text(row.tcIn)
                    .font(Theme.Typography.font(.regular, size: 12))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onRowSelected(row.id) }
            }
            .width(90)

            TableColumn("TC Out") { row in
                Text(row.tcOut)
                    .font(Theme.Typography.font(.regular, size: 12))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onRowSelected(row.id) }
            }
            .width(90)

            TableColumn("Length") { row in
                Text(row.length)
                    .font(Theme.Typography.font(.regular, size: 12))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onRowSelected(row.id) }
            }
            .width(60)

            // Opens the row's detail sheet (`ROADMAP.md` D10/T10.2:
            // `CueRowDetailView` — direct timecode edit, right-holder
            // editing) — a dedicated column rather than repurposing the
            // row's existing click-to-play gesture, which stays reachable on
            // TC In/TC Out/Length exactly as it was before this pass. Header
            // reads "Royalty Split" (not blank) since that's what this
            // column's sheet is mostly used for; icon is a gear, not the
            // three-dot "more" glyph originally used here.
            TableColumn("Royalty Split") { row in
                Button {
                    onOpenDetail(row.id)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.white)
                }
                .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                .accessibilityLabel(Text("Edit details for cue \(row.number)"))
            }
            .width(96)

            TableColumn("") { row in
                Button {
                    onDelete(row.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Colors.white)
                }
                .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                // Accessible/precise hit target for a row-scoped destructive
                // action — `SharpButtonStyle`'s own default padding is sized
                // for a full-width text button, not a table-row icon button.
                .accessibilityLabel(Text("Delete cue \(row.number)"))
            }
            .width(36)
        }
        .font(Theme.Typography.font(.regular, size: 12))
        .onChange(of: focusedTitleRowID) { _, newValue in
            onTitleFieldFocusChanged(newValue != nil)
        }
    }
}

/// The Title column's cell — a real `TextField`, backed by local `@State`
/// seeded from `row.title` so keystrokes render immediately without waiting
/// on a round-trip through the caller's debounced save (`ROADMAP.md`
/// D10/T10.2, SPEC.md §4.18). A dedicated child view, not an inline closure,
/// specifically so this `@State` survives `Table`'s own re-diffing of the
/// row closure across re-renders — SwiftUI keys per-row identity by
/// `CueTableRow.id`, so this cell's local text stays put across unrelated
/// state changes (e.g. another row's edit, playback ticking) as long as this
/// row's `id` doesn't change.
///
/// Also renders the small validation-warning glyph (`row.hasValidationIssue`)
/// leading the field — a non-blocking indicator only (SPEC.md §4.6): a cue's
/// shares can be left non-100% at edit time, this just makes that visible
/// per-row without stopping anything.
private struct EditableTitleCell: View {
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

#Preview("CueTableView") {
    CueTableView(rows: [
        CueTableRow(
            id: 0,
            number: 1,
            title: "Opening Theme",
            tcIn: "00:00:10:00",
            tcOut: "00:00:30:00",
            length: "00:20"
        ),
        CueTableRow(
            id: 1,
            number: 2,
            title: "",
            tcIn: "—",
            tcOut: "—",
            length: "00:00",
            hasValidationIssue: true
        ),
        CueTableRow(
            id: 2,
            number: 3,
            title: "End Credits",
            tcIn: "00:05:00:00",
            tcOut: "00:05:45:12",
            length: "00:45"
        ),
    ], playingRowID: 1) // row 2 shows the stop icon; the rest show play
        .frame(width: 620, height: 200)
        .padding()
}
