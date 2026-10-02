import ACDesignSystem
import SwiftUI

/// The combined Review & Export destination (`CLAUDE.md`'s Navigation
/// Model — "a single persistent screen showing both the validation summary
/// ... and the export controls ... together, inline", never a sheet).
///
/// Layout: `ReviewView` (T11.1) as a narrower left panel, `CueSheetPreviewView`
/// (T11.2) filling the remaining central space, `ExportPanelView` (T11.5) as
/// a bottom bar spanning the full width — all three on the reversed surface,
/// per `CLAUDE.md`'s Visual Language ("Review & Export uses the reversed
/// surface").
public struct ReviewAndExportView: View {
    private let viewModel: ReviewAndExportViewModel

    public init(viewModel: ReviewAndExportViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ReviewView(viewModel: viewModel.reviewViewModel)
                    .frame(width: 340)

                Divider().overlay(Theme.Surface.reversed.foreground.opacity(0.2))

                CueSheetPreviewView(viewModel: viewModel.cueSheetPreviewViewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ExportPanelView(viewModel: viewModel.exportViewModel, issues: viewModel.reviewViewModel.issues)
        }
        .background(Theme.Surface.reversed.background)
        .fixedAppearance(for: .reversed)
    }
}
