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
    /// through `onDelete` so the caller knows exactly which cue to remove,
    /// the same "plain `Int` index, never `Cue.ID`" boundary `WaveformMarker`
    /// already established.
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
public struct CueTableView: View {
    private let rows: [CueTableRow]
    private let onDelete: (Int) -> Void

    public init(rows: [CueTableRow], onDelete: @escaping (Int) -> Void = { _ in }) {
        self.rows = rows
        self.onDelete = onDelete
    }

    public var body: some View {
        Table(rows) {
            TableColumn("#") { row in
                Text("\(row.number)")
                    .font(Theme.Typography.font(.regular, size: 12))
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
            }

            TableColumn("TC In") { row in
                Text(row.tcIn)
                    .font(Theme.Typography.font(.regular, size: 12))
                    .monospacedDigit()
            }
            .width(90)

            TableColumn("TC Out") { row in
                Text(row.tcOut)
                    .font(Theme.Typography.font(.regular, size: 12))
                    .monospacedDigit()
            }
            .width(90)

            TableColumn("Length") { row in
                Text(row.length)
                    .font(Theme.Typography.font(.regular, size: 12))
                    .monospacedDigit()
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
    ])
    .frame(width: 500, height: 200)
    .padding()
}
