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

    public init(viewModel: CueDetectionReviewViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("\(viewModel.cues.count) cue\(viewModel.cues.count == 1 ? "" : "s") detected")
                .font(Theme.Typography.font(.medium, size: 13))
                .foregroundStyle(Theme.Surface.primary.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)

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
            .frame(minHeight: 160)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Surface.primary.background)
        .errorAlert(message: $viewModel.errorMessage)
        .task { await viewModel.load() }
        .task { viewModel.startObservingPlayback() }
    }
}
