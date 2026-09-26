import ACDesignSystem
import SwiftUI

/// The waveform review/correction surface (`ROADMAP.md` D9/T9.3) — reached
/// automatically once `CueSheetSectionViewModel` (D9/T9.5) observes
/// `Project.cues` populated, whether from a fresh detection run or a
/// reopened, already-processed project. Cue Sheet section screens use the
/// primary surface (`CLAUDE.md`, "Visual Language") — `WaveformView` itself
/// keeps its own reversed (dark) background regardless, the standard
/// waveform-visualizer convention independent of the surrounding screen.
public struct CueDetectionReviewView: View {
    @Bindable private var viewModel: CueDetectionReviewViewModel
    /// `ProjectWindowView`'s already-existing, per-window instance — the
    /// same one `SetupView` uses (`ROADMAP.md` D10/T10.3) — so
    /// `CueRowDetailView`'s embedded `CueRightHolderEditorView` reuses the
    /// existing `PartyPickerView`/directory rather than a second, redundant
    /// one.
    private let directoryViewModel: RightHolderDirectoryViewModel
    @FocusState private var isFocused: Bool
    @State private var isConfirmingClearAudio = false
    @State private var rowDetailTarget: RowDetailTarget?
    /// **Real bug found during manual testing, not anticipated at design
    /// time:** without this, typing a space into `CueTableView`'s new
    /// editable Title field was silently swallowed by this screen's own
    /// `.onKeyPress(.space)` handler below (D9's play/pause spacebar
    /// shortcut) before the `TextField` ever saw it — confirmed live:
    /// typing "Test Theme" produced "TestTheme," every space eaten by
    /// `togglePlayback()` firing instead. `CueTableView` reports whether any
    /// of its title fields currently has focus via `onTitleFieldFocusChanged`;
    /// this screen uses that to disable the spacebar shortcut for exactly as
    /// long as a title is actually being edited.
    @State private var isEditingCueTitle = false
    /// `ProjectWindowView` constructs this window's own `UndoManager` and
    /// passes it here directly — a plain `init` parameter, not SwiftUI's
    /// environment (`ProjectUndoManagerFocusedValue.swift`, App target,
    /// explains why: SwiftUI's built-in `\.undoManager` environment key is
    /// read-only, reserved for `DocumentGroup`/`NSDocument` scenes). Real
    /// ⌘Z/⌘⇧Z menu wiring is separate, via `FocusedValues` — this reference
    /// exists only so `CueTableView`'s ✕ delete button can pass it to
    /// `viewModel.deleteCue`, which registers the actual inverse action on
    /// it, per SPEC.md §4.18.
    private let undoManager: UndoManager?

    /// A fixed icon footprint for every header-row button (play/stop, zoom
    /// out, zoom in, remove-file) — found during manual testing that the
    /// zoom buttons rendered visibly shorter than the others, despite all
    /// four sharing the same `SharpButtonStyle` (same padding, same label
    /// font size): different SF Symbols aren't guaranteed the same glyph
    /// bounding-box height at a given point size (`plus.magnifyingglass`/
    /// `minus.magnifyingglass` measure shorter than `play.fill`/`stop.fill`/
    /// `xmark` here), so `SharpButtonStyle`'s otherwise-identical padding
    /// still produced visibly different total button heights. Framing every
    /// icon to the same explicit box removes the per-symbol metric
    /// difference entirely, rather than tuning a font size per icon.
    private static let headerIconSize: CGFloat = 16

    public init(
        viewModel: CueDetectionReviewViewModel,
        directoryViewModel: RightHolderDirectoryViewModel,
        undoManager: UndoManager?
    ) {
        self.viewModel = viewModel
        self.directoryViewModel = directoryViewModel
        self.undoManager = undoManager
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("\(viewModel.cues.count) cue\(viewModel.cues.count == 1 ? "" : "s") detected")
                        .font(Theme.Typography.font(.medium, size: 13))
                        .foregroundStyle(Theme.Surface.primary.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Explicit transport control — until now the only way
                    // to start playback was a waveform click, and there was
                    // no way to stop one short of retargeting it elsewhere.
                    Button {
                        viewModel.togglePlayback()
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                            .frame(width: Self.headerIconSize, height: Self.headerIconSize)
                    }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))

                    // Button-triggered waveform zoom — moved here from
                    // an in-waveform overlay so it sits with the other
                    // transport-adjacent controls in the header row.
                    Button {
                        viewModel.zoom(by: 1 / 1.5)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .frame(width: Self.headerIconSize, height: Self.headerIconSize)
                    }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))

                    Button {
                        viewModel.zoom(by: 1.5)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .frame(width: Self.headerIconSize, height: Self.headerIconSize)
                    }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))

                    // "Wrong file" recovery — clears audioAsset/
                    // waveformPeaks/cues and returns to AudioImportView via
                    // CueSheetSectionViewModel's own resume-state routing.
                    // Confirmed first: this discards every detected/edited
                    // cue, a real, not-undoable loss of work.
                    Button {
                        isConfirmingClearAudio = true
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: Self.headerIconSize, height: Self.headerIconSize)
                    }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                    .confirmationDialog(
                        "Clear imported audio?",
                        isPresented: $isConfirmingClearAudio,
                        titleVisibility: .visible
                    ) {
                        Button("Clear Audio & Cues", role: .destructive) {
                            viewModel.clearImportedAudio()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Removes the audio, the waveform, and every detected or edited cue. This can't be undone.")
                    }
                }

                // Capped at roughly a third of this screen's own height —
                // CueTableView (D10/T10.2, minimal pull-forward) now fills
                // the remainder below it, per the proportions this layout
                // was left room for from the start.
                WaveformView(
                    displayData: viewModel.displayData,
                    markers: viewModel.markers,
                    visibleRangeSeconds: $viewModel.visibleRangeSeconds,
                    fileDurationSeconds: viewModel.fileDurationSeconds,
                    playheadOffsetSeconds: viewModel.playheadOffsetSeconds,
                    onBoundaryDragged: { marker, seconds in
                        viewModel.boundaryDragged(marker: marker, toSeconds: seconds, undoManager: undoManager)
                    },
                    onMergeRequested: { markerID in viewModel.mergeRequested(
                        markerID: markerID,
                        undoManager: undoManager
                    ) },
                    onSplitRequested: { seconds in
                        viewModel.splitRequested(atSeconds: seconds, undoManager: undoManager)
                    },
                    onPlayFromPoint: viewModel.playFromPoint,
                    onPlayMarkerSpan: viewModel.playMarkerSpan,
                    onVisibleRangeChanged: viewModel.visibleRangeChanged
                )
                .frame(height: max(160, geometry.size.height / 3))

                // Row click plays that cue's span — the same
                // play-cue-span mechanism (`playMarkerSpan`) a waveform
                // marker click already triggers, just a second entry
                // point into it, so a cut-off cue start can be audited
                // directly from the list. The leading icon is the one
                // control that also stops — everywhere else in the row
                // only ever starts playback.
                CueTableView(
                    rows: viewModel.tableRows,
                    playingRowID: viewModel.playingCueID,
                    onRowSelected: viewModel.playMarkerSpan,
                    onPlayToggle: viewModel.toggleRowPlayback,
                    onTitleChanged: { index, newTitle in
                        guard viewModel.cues.indices.contains(index) else { return }
                        viewModel.titleChanged(cueID: viewModel.cues[index].id, newTitle: newTitle)
                    },
                    onOpenDetail: { index in
                        rowDetailTarget = RowDetailTarget(id: index)
                    },
                    onDelete: { index in
                        viewModel.deleteCue(at: index, undoManager: undoManager)
                    },
                    onTitleFieldFocusChanged: { isEditing in
                        isEditingCueTitle = isEditing
                    }
                )
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.Surface.primary.background)
        .errorAlert(message: $viewModel.errorMessage)
        .focusable()
        .focused($isFocused)
        .onKeyPress(.space) {
            guard !isEditingCueTitle else { return .ignored }
            viewModel.togglePlayback()
            return .handled
        }
        .task { await viewModel.load() }
        .task { viewModel.startObservingPlayback() }
        .task { isFocused = true }
        // `SetupView` already loads this same, per-window
        // `directoryViewModel` instance — but a user who switches straight
        // to the Cues tab without ever visiting Setup first would otherwise
        // see an empty right-holder directory here. Safe to call again:
        // `loadDirectory()`'s own doc comment states it's idempotent/safe to
        // call repeatedly.
        .task { await directoryViewModel.loadDirectory() }
        .sheet(item: $rowDetailTarget) { target in
            CueRowDetailView(
                cueIndex: target.id,
                viewModel: viewModel,
                directoryViewModel: directoryViewModel,
                undoManager: undoManager,
                onDismiss: { rowDetailTarget = nil }
            )
        }
    }
}

/// Wraps a row index as `Identifiable` for `.sheet(item:)` — `Int` itself
/// isn't `Identifiable`, and a plain `Bool`/index pair would need to be kept
/// in sync manually the way `PartyPickerView`'s own `personBeingEdited`/
/// `labelBeingEdited` avoid by using `.sheet(item:)` in the first place.
private struct RowDetailTarget: Identifiable {
    let id: Int
}
