import ACCore
import ACDesignSystem
import CoreGraphics
import SwiftUI

/// Draws the identical, precomputed `[CueSheetPageLayout]` overlay content
/// `WAFormRenderer` (`ACExport`) also draws, **on top of the user's own
/// imported WA Film template pages** (`ROADMAP.md` D12/T12.4) — the same
/// preview/export pixel-identity guarantee `CueSheetPreviewView` (D11/T11.2)
/// already establishes, extended here to a document whose background is a
/// real file this app never bundles (`CLAUDE.md`, "Export Architecture").
///
/// **Opens `viewModel.templateFileURLs` directly — no bookmark resolution
/// or security-scoped access bracketing of its own.** A real simplification
/// from this View's original design (`docs/DECISIONS.md`, D12/T12.4): the
/// template is AutoCue's own private copy inside its sandbox container, not
/// a user-selected external location, so the app always has standing read
/// access to it (`WAFormTemplateRepository.templateFileURLs()`'s own doc
/// comment).
///
/// **A real coordinate-flip risk, distinct from `CueSheetPreviewView`'s own
/// already-fixed one — flagged and verified, not assumed.** `Canvas`'s raw
/// `CGContext` (via `GraphicsContext.withCGContext`) is top-left-origin,
/// y-down, to match SwiftUI's own view-hosted drawing convention.
/// `CGPDFPage`/`context.drawPDFPage(_:)` — like `CTFrameDraw`, the bug
/// `CueSheetPreviewView` already found and fixed at D11/T11.5 — assumes the
/// opposite, native bottom-left-origin, y-up space (the same space
/// `WAFormRenderer`'s own raw `PDFContext` natively is, which is exactly why
/// that renderer needs no flip before its own `drawPDFPage` call). Left
/// uncorrected here, the real template page would render upside-down. The
/// fix, applied once per page before `drawPDFPage` (and nowhere else — the
/// overlay elements drawn afterward are already correct in `Canvas`'s native
/// space via `CanvasElementDrawing`, unaffected by this page-level flip):
/// translate by the page's own height, flip the y-scale, draw, restore.
public struct WAFormPreviewView: View {
    @Bindable private var viewModel: WAFilmFormViewModel

    @State private var mainFormDocument: CGPDFDocument?
    @State private var continuationFormDocument: CGPDFDocument?
    @State private var documentLoadErrorMessage: String?

    public init(viewModel: WAFilmFormViewModel) {
        _viewModel = Bindable(viewModel)
    }

    /// Matches `WAFormLayoutComputer`'s own page geometry exactly —
    /// duplicated here rather than shared, since `ACFeatures` cannot depend
    /// on `ACExport` (`CLAUDE.md`'s Package Dependency Graph).
    private static let pageWidth: CGFloat = 595.7
    private static let pageHeight: CGFloat = 841.227

    /// The main form always occupies exactly the first 2 pages of
    /// `viewModel.previewPages` (works 1–2 on page 1, works 3–5 on page 2 —
    /// a real, confirmed, fixed split, `SPEC.md` §2.1/§4.24); every page
    /// after that maps to the continuation document's own pages in order.
    /// Matches `ExportRepositoryImpl.exportWAForm`'s own hardcoded
    /// `mainPageCount: 2` exactly — not an independently-derived number.
    private static let mainFormPageCount = 2

    public var body: some View {
        Group {
            if viewModel.projectNotFound {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Project Not Found",
                    message: "This project may have been deleted.",
                    surface: .reversed
                )
            } else if let message = viewModel.templateAccessErrorMessage ?? documentLoadErrorMessage {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn't Load Template",
                    message: message,
                    surface: .reversed
                )
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        ForEach(Array(viewModel.previewPages.enumerated()), id: \.offset) { index, page in
                            pageView(page, index: index)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Surface.reversed.background)
        .task(id: viewModel.templateFileURLs?.mainFormURL) {
            loadDocuments()
        }
    }

    private func pageView(_ page: CueSheetPageLayout, index: Int) -> some View {
        Canvas { context, _ in
            draw(page, index: index, in: context)
        }
        .frame(width: Self.pageWidth, height: Self.pageHeight)
        .background(Color.white)
    }

    private func draw(_ page: CueSheetPageLayout, index: Int, in context: GraphicsContext) {
        context.withCGContext { cgContext in
            if let templatePage = templatePage(forIndex: index) {
                cgContext.saveGState()
                cgContext.translateBy(x: 0, y: Self.pageHeight)
                cgContext.scaleBy(x: 1, y: -1)
                cgContext.drawPDFPage(templatePage)
                cgContext.restoreGState()
            }
            CanvasElementDrawing.drawElements(page.elements, in: cgContext)
        }
    }

    private func templatePage(forIndex index: Int) -> CGPDFPage? {
        if index < Self.mainFormPageCount {
            mainFormDocument?.page(at: index + 1)
        } else {
            continuationFormDocument?.page(at: index - Self.mainFormPageCount + 1)
        }
    }

    private func loadDocuments() {
        documentLoadErrorMessage = nil
        guard let urls = viewModel.templateFileURLs else {
            mainFormDocument = nil
            continuationFormDocument = nil
            return
        }
        guard
            let mainDocument = CGPDFDocument(urls.mainFormURL as CFURL),
            let continuationDocument = CGPDFDocument(urls.continuationFormURL as CFURL)
        else {
            documentLoadErrorMessage = "Couldn't open the imported WA Film template."
            return
        }
        mainFormDocument = mainDocument
        continuationFormDocument = continuationDocument
    }
}
