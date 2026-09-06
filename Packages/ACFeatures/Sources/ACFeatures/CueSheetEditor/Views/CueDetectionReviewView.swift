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

    public init(viewModel: CueDetectionReviewViewModel) {
        self.viewModel = viewModel
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

                // Capped at roughly a third of this screen's own height,
                // deliberately leaving the remainder empty for now — D10's
                // cue list (CueTableView) lands below this, not yet wired
                // in, but the proportions are right from the start rather
                // than a full-height waveform that would need redoing.
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

                Spacer(minLength: 0)
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
