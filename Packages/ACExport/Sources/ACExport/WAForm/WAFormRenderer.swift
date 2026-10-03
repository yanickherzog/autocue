import ACCore
import CoreGraphics
import Foundation

/// Draws `[CueSheetPageLayout]` (`WAFormLayoutComputer`'s overlay-only
/// output, `ROADMAP.md` D12) onto the user's own real WA Film template
/// pages — plain Core Graphics (`CGPDFDocument`/`context.drawPDFPage`),
/// never `PDFKit` (`CLAUDE.md`, "Export Architecture"). Writes a brand-new
/// output PDF; the user's stored template files are never modified.
///
/// **The first `mainPageCount` layout pages draw onto `mainFormDocument`'s
/// own pages, in order; every page after that draws onto
/// `continuationFormDocument`'s pages, in order** — matching exactly how
/// `WAFormLayoutComputer.computeLayout(for:continuationPagesAvailable:)`
/// constructs its own page list (the main form's fixed 2 pages always
/// first, continuation pages after).
///
/// Same coordinate convention as `PDFCueSheetRenderer`: `LayoutRect.y`
/// increases downward from the page top; this renderer is the one place
/// that flips to Core Graphics' native bottom-left-origin space.
enum WAFormRenderer {
    enum RenderError: Error {
        case couldNotCreateDataConsumer
        case couldNotCreatePDFContext
        case missingTemplatePage(documentPageIndex: Int)
    }

    static func render(
        _ pages: [CueSheetPageLayout],
        mainFormDocument: CGPDFDocument,
        continuationFormDocument: CGPDFDocument,
        mainPageCount: Int,
        to url: URL
    ) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw RenderError.couldNotCreateDataConsumer
        }
        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: WAFormLayoutComputer.pageWidth,
            height: WAFormLayoutComputer.pageHeight
        )
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw RenderError.couldNotCreatePDFContext
        }

        for (index, page) in pages.enumerated() {
            let isMainFormPage = index < mainPageCount
            let documentPageIndex = isMainFormPage ? index : index - mainPageCount
            let document = isMainFormPage ? mainFormDocument : continuationFormDocument
            // CGPDFDocument pages are 1-indexed.
            guard let templatePage = document.page(at: documentPageIndex + 1) else {
                throw RenderError.missingTemplatePage(documentPageIndex: documentPageIndex)
            }

            context.beginPDFPage(nil)
            context.saveGState()
            context.drawPDFPage(templatePage)
            context.restoreGState()
            draw(page, in: context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    private static func draw(_ page: CueSheetPageLayout, in context: CGContext) {
        let pageHeight = WAFormLayoutComputer.pageHeight
        for element in page.elements {
            let flippedFrame = CGRect(
                x: element.frame.x,
                y: pageHeight - element.frame.y - element.frame.height,
                width: element.frame.width,
                height: element.frame.height
            )
            switch element.content {
            case let .text(string, font):
                PDFElementDrawing.drawText(string, font: font, in: flippedFrame, context: context)
            case let .rule(spec):
                PDFElementDrawing.drawRule(spec, in: flippedFrame, context: context)
            }
        }
    }
}
