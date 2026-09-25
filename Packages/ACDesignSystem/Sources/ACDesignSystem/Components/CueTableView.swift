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

    public init(id: Int, number: Int, title: String, tcIn: String, tcOut: String, length: String) {
        self.id = id
        self.number = number
        self.title = title
        self.tcIn = tcIn
        self.tcOut = tcOut
        self.length = length
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
public struct CueTableView: View {
    private let rows: [CueTableRow]
    private let playingRowID: Int?
    private let onRowSelected: (Int) -> Void
    private let onPlayToggle: (Int) -> Void
    private let onDelete: (Int) -> Void

    public init(
        rows: [CueTableRow],
        playingRowID: Int? = nil,
        onRowSelected: @escaping (Int) -> Void = { _ in },
        onPlayToggle: @escaping (Int) -> Void = { _ in },
        onDelete: @escaping (Int) -> Void = { _ in }
    ) {
        self.rows = rows
        self.playingRowID = playingRowID
        self.onRowSelected = onRowSelected
        self.onPlayToggle = onPlayToggle
        self.onDelete = onDelete
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

            TableColumn("Title") { row in
                Text(row.title.isEmpty ? "Untitled" : row.title)
                    .font(Theme.Typography.font(.regular, size: 12))
                    .foregroundStyle(
                        row.title.isEmpty
                            ? Theme.Colors.ghostTextPrimary
                            : Theme.Surface.primary.foreground
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onRowSelected(row.id) }
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
        CueTableRow(id: 1, number: 2, title: "", tcIn: "—", tcOut: "—", length: "00:00"),
        CueTableRow(id: 2, number: 3, title: "End Credits", tcIn: "00:05:00:00", tcOut: "00:05:45:12", length: "00:45"),
    ], playingRowID: 1) // row 2 shows the stop icon; the rest show play
        .frame(width: 500, height: 200)
        .padding()
}
