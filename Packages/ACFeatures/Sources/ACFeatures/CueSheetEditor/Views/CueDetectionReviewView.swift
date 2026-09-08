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
    @FocusState private var isFocused: Bool
    @State private var isConfirmingClearAudio = false
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

    public init(viewModel: CueDetectionReviewViewModel, undoManager: UndoManager?) {
        self.viewModel = viewModel
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
                    }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))

                    // Button-triggered waveform zoom — moved here from
                    // an in-waveform overlay so it sits with the other
                    // transport-adjacent controls in the header row.
                    Button {
                        viewModel.zoom(by: 1 / 1.5)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))

                    Button {
                        viewModel.zoom(by: 1.5)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
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
                    onBoundaryDragged: viewModel.boundaryDragged,
                    onMergeRequested: viewModel.mergeRequested,
                    onSplitRequested: viewModel.splitRequested,
                    onPlayFromPoint: viewModel.playFromPoint,
                    onPlayMarkerSpan: viewModel.playMarkerSpan,
                    onVisibleRangeChanged: viewModel.visibleRangeChanged
                )
                .frame(height: max(160, geometry.size.height / 3))

                CueTableView(rows: viewModel.tableRows) { index in
                    viewModel.deleteCue(at: index, undoManager: undoManager)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.Surface.primary.background)
        .errorAlert(message: $viewModel.errorMessage)
        .focusable()
        .focused($isFocused)
        .onKeyPress(.space) {
            viewModel.togglePlayback()
            return .handled
        }
        .task { await viewModel.load() }
        .task { viewModel.startObservingPlayback() }
        .task { isFocused = true }
    }
}
