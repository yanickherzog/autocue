import ACDesignSystem
import SwiftUI

/// The WA Film tab's root content (`ROADMAP.md` D12/T12.4) — the fourth,
/// always-visible `ProjectSection`, a real change to `CLAUDE.md`'s
/// Navigation Model. Mirrors `ReviewAndExportView`'s layout shape (left
/// panel / center preview / bottom export bar, all on the reversed surface
/// per `CLAUDE.md`'s Visual Language) but backed by one ViewModel rather
/// than three composed ones — see `WAFilmFormViewModel`'s own doc comment
/// for why.
///
/// **Empty state is the full-screen template-import prompt, not a smaller
/// inline element** — per `ROADMAP.md` T12.4's own Task text ("the tab's own
/// empty state is the template-import prompt"), matching `AudioImportView`'s
/// established shape for an analogous "nothing to show until the user
/// completes a one-time setup step" screen.
public struct WAFilmFormView: View {
    @Bindable private var viewModel: WAFilmFormViewModel

    public init(viewModel: WAFilmFormViewModel) {
        _viewModel = Bindable(viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.currentTemplate == nil {
                WAFormImportPromptView(viewModel: viewModel)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        WAFormStatusPanel(viewModel: viewModel)
                            .frame(width: 340)

                        Divider().overlay(Theme.Surface.reversed.foreground.opacity(0.2))

                        WAFormPreviewView(viewModel: viewModel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    WAFormExportPanelView(viewModel: viewModel)
                }
                .background(Theme.Surface.reversed.background)
                .fixedAppearance(for: .reversed)
            }
        }
        .task {
            await viewModel.load()
        }
    }
}
