import AppKit
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
    private let onOpenRecordingInfo: (Int) -> Void
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
        onOpenRecordingInfo: @escaping (Int) -> Void = { _ in },
        onDelete: @escaping (Int) -> Void = { _ in },
        onTitleFieldFocusChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.rows = rows
        self.playingRowID = playingRowID
        self.onRowSelected = onRowSelected
        self.onPlayToggle = onPlayToggle
        self.onTitleChanged = onTitleChanged
        self.onOpenDetail = onOpenDetail
        self.onOpenRecordingInfo = onOpenRecordingInfo
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
            // competes with auditioning a cue's boundaries. Header reads
            // "Cue Title" (not "Title") — real manual testing found "Title"
            // read ambiguously next to "Royalty Split"/"Label"; this column
            // deliberately stays the one flexible-width column (no
            // `.width()`), so the space freed up by narrowing the two
            // detail-icon columns flows here automatically.
            TableColumn("Cue Title") { row in
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
            // column's sheet is mostly used for. The icon is now
            // center-aligned within the column (found during real manual
            // testing that it sat at the leading edge); the header's own
            // title text stays left-aligned — no public SwiftUI API centers
            // a `TableColumn` header on macOS, see `detailIconColumn`'s own
            // doc comment below. Extracted into that shared function, used
            // by the "Label" column immediately after too — partly to avoid
            // duplicating this identical shape twice, partly because
            // inlining both here pushed this `Table`'s column-builder
            // expression past the type checker's time limit.
            detailIconColumn(title: "Royalty Split", accessibilityVerb: "Edit details for", action: onOpenDetail)

            // Opens the row's Label sheet (`Cue.recordingLabel`/
            // `.recordingLabelNumber`/`.recordingISRC`) — a separate column
            // and a separate sheet from "Royalty Split" above, since the two
            // edit genuinely unrelated data (a licensed/pre-existing
            // recording's own identity vs. this work's right-holder split).
            // Same gear icon/size/button style as "Royalty Split" — a real,
            // project-owner-requested change from this column's original,
            // distinct `tag` icon, for visual consistency between the two
            // detail-sheet columns.
            detailIconColumn(title: "Label", accessibilityVerb: "Edit label for", action: onOpenRecordingInfo)

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

    /// Shared shape for "Royalty Split"/"Label" — a center-aligned gear icon
    /// button, sized to a real measured fixed width (`measuredDetailColumnWidth`
    /// below), not a guessed round number. See `body`'s own comment for why
    /// this is a real function, not two inlined `TableColumn`s.
    ///
    /// **The column header's own title text cannot be centered — a real,
    /// confirmed platform limitation, not a style choice left undone.**
    /// `TableColumn` has no `alignment:` parameter on macOS (confirmed by a
    /// real compiler error attempting one), and its only `Content`-closure
    /// initializer constrains `Label == Text` with no way to substitute a
    /// custom header view (also confirmed by a real compiler error, not
    /// assumed) — there is no public API on this SDK for centering a
    /// `TableColumn`'s own header text. Only the icon inside the cell is
    /// centered here; the header above it stays left-aligned, same as every
    /// other column's header in this table.
    private func detailIconColumn(
        title: String,
        accessibilityVerb: String,
        action: @escaping (Int) -> Void
    ) -> some TableColumnContent<CueTableRow, Never> {
        TableColumn(title) { row in
            Button {
                action(row.id)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.white)
            }
            .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
            .accessibilityLabel(Text("\(accessibilityVerb) cue \(row.number)"))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .width(Self.measuredDetailColumnWidth(headerTitle: title))
    }

    /// **Real measurement, not a guessed round number — the same discipline
    /// `CueSheetLayoutComputer+Measurement.swift`'s PDF column-width code
    /// already establishes, applied here to this `Table`'s own real header
    /// rendering.**
    ///
    /// **A first version of this measurement was wrong, and the fix is
    /// recorded here rather than silently corrected — real evidence, not a
    /// re-guess.** It measured `NSTableHeaderCell(textCell:).cellSize`
    /// against a *default* cell, which reports AppKit's own built-in
    /// header font — `.SFNS-Regular` 11pt, confirmed via a real,
    /// standalone measurement script before that version shipped. That's
    /// the font a *plain* `NSTableHeaderView` uses, but it is **not** the
    /// font this `Table` actually draws its headers in: `body`'s own
    /// `.font(Theme.Typography.font(.regular, size: 12))` modifier (line
    /// ~244) is applied to the whole `Table`, and on this SDK that
    /// environment value propagates into the header title text too, not
    /// only into cell content — confirmed two ways, not assumed: (1) a real
    /// screenshot of the running app showed "Royalty Split" truncated to
    /// "Royalty S…" even though the old measurement's 69pt budget was
    /// supposedly wide enough for an 11pt system-font rendering of that
    /// string; (2) a standalone measurement script loading the real bundled
    /// `SpaceGrotesk-Regular.ttf` at 12pt (`Theme.FontWeight.regular`, the
    /// exact weight/size `body`'s own modifier requests) measured "Royalty
    /// Split" at ≈74.6pt raw — wider than the old 69pt total budget before
    /// any padding was even added, which fully explains the observed
    /// truncation. **Two other candidate causes were checked and ruled out:**
    /// no `TableColumn` here uses `sortUsing:`/a `SortComparator` (confirmed
    /// by grep), so no header reserves sort-indicator space; the
    /// column-resize handle draws at the column boundary, not subtracted
    /// from any one column's own content width.
    ///
    /// **The fix measures against the real font** — `NSFont(name:
    /// Theme.FontWeight.regular.postScriptName, size: 12)`, the identical
    /// PostScript name/size `Theme.Typography.font(.regular, size: 12)`
    /// wraps, so this can never silently drift from what `body`'s own
    /// modifier actually requests — via `NSAttributedString.size(withAttributes:)`.
    /// **Plus a small, explicit `headerSafetyMargin` of 6pt (3pt a side),
    /// not folded silently into the measurement:** raw glyph-run
    /// measurement can slightly under-report a string's real on-screen
    /// footprint (sub-pixel anti-aliasing/hinting rounding at render time —
    /// a different, smaller concern than "which font," the actual bug
    /// here), and `NSTableHeaderCell`'s own padding figure is no longer
    /// used at all (it reports a default cell's layout, not this
    /// SwiftUI-rendered header's). 6pt is deliberately small: enough to
    /// absorb that rounding, not enough to paper over a real future
    /// measurement error.
    ///
    /// Compared against the gear button's own real natural width
    /// (`SharpButtonStyle`'s actual `Theme.Spacing.md` horizontal padding
    /// either side of the real rendered `gearshape` glyph size at this
    /// button's actual point size/weight, read via `NSImage.SymbolConfiguration`
    /// rather than guessed) — whichever is wider wins, so the header is
    /// never clipped and the button is never visually cramped. Every
    /// measurement here is a real API call against the real font/icon
    /// actually drawn, not a hardcoded constant, so this stays correct if
    /// either title, `body`'s own font modifier, or the icon's own
    /// size/weight/padding ever changes.
    /// Not `private`: `ACDesignSystemTests` calls this directly (via
    /// `@testable import`) to assert a header's measured width is never
    /// smaller than its real text width at the real font — the exact
    /// regression this function itself was written to fix. `internal` (the
    /// default) still keeps it out of this package's public API.
    static func measuredDetailColumnWidth(headerTitle: String) -> CGFloat {
        let headerSafetyMargin: CGFloat = 6

        let headerFont = NSFont(name: Theme.FontWeight.regular.postScriptName, size: 12)
            ?? NSFont.systemFont(ofSize: 12)
        let headerTextWidth = (headerTitle as NSString).size(withAttributes: [.font: headerFont]).width
        let headerWidth = headerTextWidth + headerSafetyMargin

        let iconConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let iconSize = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfiguration)?.size ?? CGSize(width: 15, height: 15)
        let buttonWidth = iconSize.width + Theme.Spacing.md * 2

        return ceil(max(headerWidth, buttonWidth))
    }
}

// `EditableTitleCell` lives in its own file, `EditableTitleCell.swift` —
// moved out once this file grew past this project's file-length lint
// limit; see that file's own doc comment.

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
