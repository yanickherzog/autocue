import ACDesignSystem
import SwiftUI

/// A transient progress indicator for a cue-detection run (`ROADMAP.md`
/// D9/T9.2) — not where correction happens (`SPEC.md` §4.19); the waveform
/// review/correction surface is `CueDetectionReviewView` (D9/T9.3), reached
/// automatically once detection completes (`CueSheetSectionViewModel`,
/// D9/T9.5).
public struct CueDetectionProgressView: View {
    @Bindable private var viewModel: CueDetectionViewModel

    public init(viewModel: CueDetectionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            switch viewModel.phase {
            case .idle, .detecting:
                ProgressBanner(message: "Detecting cues…", fractionCompleted: fractionCompleted)
            case .completed:
                // Momentary — `CueSheetSectionViewModel` swaps this screen
                // out for `CueDetectionReviewView` the instant `Project.cues`
                // populates, so this state is rarely, if ever, actually seen.
                ProgressBanner(message: "Detecting cues…", fractionCompleted: 1.0)
            case let .failed(message):
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Cue Detection Failed",
                    message: message,
                    surface: .primary
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Surface.primary.background)
        .task {
            // `resetIfNeeded()` must run before `runDetectionIfNeeded()`,
            // in the same `.task` closure — see `resetIfNeeded()`'s doc
            // comment for why a stale `.completed`/`.failed` phase from a
            // previous import/clear cycle would otherwise silently block
            // this cycle's detection from ever starting. Two separate
            // `.task` modifiers (one here, one at the call site) would not
            // guarantee this ordering — SwiftUI doesn't promise which of
            // two independent `.task`s attached to the same appearing view
            // runs first.
            viewModel.resetIfNeeded()
            viewModel.runDetectionIfNeeded()
        }
    }

    private var fractionCompleted: Double? {
        if case let .detecting(fraction) = viewModel.phase {
            return fraction
        }
        return nil
    }
}
