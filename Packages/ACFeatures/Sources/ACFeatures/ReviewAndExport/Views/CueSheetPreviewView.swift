import ACCore
import ACDesignSystem
import CoreGraphics
import SwiftUI

/// Draws the identical, precomputed `[CueSheetPageLayout]`
/// `PDFCueSheetRenderer` (`ACExport`) also draws — `ROADMAP.md` D11/T11.2,
/// built in the same Task as the layout computation and the PDF renderer so
/// preview and export are verified against each other directly from day one
/// (per the project owner's own explicit reasoning for pulling this into
/// T11.2 rather than deferring to T11.5).
///
/// **Deliberately drops down to a raw `CGContext` via
/// `GraphicsContext.withCGContext`, and draws text via the same
/// `CTFramesetter`/`CTFrameDraw` calls `PDFCueSheetRenderer` uses — never
/// SwiftUI's native `Text` view inside this `Canvas`.** This is the actual
/// mechanism behind `CLAUDE.md`'s "the preview View deliberately does not
/// use SwiftUI's native `Text`/`VStack` layout for the form content": using
/// `Text` here would route through SwiftUI's own text engine, which can
/// disagree with Core Text's line-breaking/wrapping — exactly the silent
/// preview/export divergence this whole architecture exists to prevent.
/// `ACFeatures` cannot depend on `ACExport` (`CLAUDE.md`'s Package
/// Dependency Graph), so this draw logic is necessarily a separate copy
/// from `PDFCueSheetRenderer`'s — but it calls the identical Core Text APIs
/// against a `CGContext`, so the two can't visually diverge regardless of
/// being two source files, the same guarantee as the font-name mapping this
/// screen's own drawing duplicates from `ACExport`'s `PDFFontMapping`.
///
/// **The actual draw primitives (`drawText`/`drawRule`/`fontName`) moved to
/// the shared `CanvasElementDrawing` at `ROADMAP.md` D12/T12.4** — the
/// moment a second `Canvas`-hosted preview (`WAFormPreviewView`) needed the
/// identical logic, per `CLAUDE.md` rule 7. This View's own behavior is
/// completely unchanged by that extraction — see `CanvasElementDrawing`'s
/// own doc comment for why sharing this specific, bug-prone primitive is
/// worth doing on the first real second-caller, not deferred to a third.
public struct CueSheetPreviewView: View {
    @Bindable var viewModel: CueSheetPreviewViewModel

    public init(viewModel: CueSheetPreviewViewModel) {
        _viewModel = Bindable(viewModel)
    }

    /// A4 landscape, matching `CueSheetLayoutComputer`'s own page geometry
    /// exactly — duplicated here rather than shared for the same
    /// cross-package reason as the font mapping above.
    private static let pageWidth: CGFloat = 841.89
    private static let pageHeight: CGFloat = 595.28

    public var body: some View {
        Group {
            if viewModel.projectNotFound {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Project Not Found",
                    message: "This project may have been deleted.",
                    surface: .reversed
                )
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { _, page in
                            pageView(page)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Surface.reversed.background)
        .task {
            await viewModel.load()
        }
    }

    private func pageView(_ page: CueSheetPageLayout) -> some View {
        Canvas { context, _ in
            draw(page, in: context)
        }
        .frame(width: Self.pageWidth, height: Self.pageHeight)
        .background(Color.white)
    }

    private func draw(_ page: CueSheetPageLayout, in context: GraphicsContext) {
        context.withCGContext { cgContext in
            // `Canvas`'s own coordinate space already matches `LayoutRect`'s
            // convention (top-left origin, y increasing downward) for plain
            // rect/line geometry — unlike `PDFCueSheetRenderer`'s Core
            // Graphics `PDFContext`, no *frame-position* flip is needed
            // here. `CTFrameDraw` itself still needs a local correction
            // regardless — see `CanvasElementDrawing.drawText`'s own doc
            // comment (real, confirmed fix, `ROADMAP.md` D11/T11.5 manual
            // verification).
            CanvasElementDrawing.drawElements(page.elements, in: cgContext)
        }
    }
}
