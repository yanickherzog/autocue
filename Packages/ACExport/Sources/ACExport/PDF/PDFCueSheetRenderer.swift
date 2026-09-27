import ACCore
import CoreGraphics
import CoreText
import Foundation

/// Draws `[CueSheetPageLayout]` (SPEC.md §4.16, `ROADMAP.md` D11/T11.2) into
/// a real PDF via Core Graphics `PDFContext` + Core Text — never `PDFKit`,
/// which is a viewing/annotation framework, not a generation mechanism
/// (`CLAUDE.md`, "Export Architecture"). Draws the identical, precomputed
/// layout the on-screen preview View also draws — neither this renderer nor
/// the preview re-derives layout independently.
///
/// **Coordinate convention, stated once here since both consumers of
/// `CueSheetPageLayout` must agree on it:** `LayoutRect.y` increases
/// *downward* from the top of the page, matching `CueSheetLayoutComputer`'s
/// own top-down layout math and SwiftUI `Canvas`'s native coordinate space
/// (so the preview needs no flip). Core Graphics' own native PDF coordinate
/// space is bottom-left-origin with `y` increasing *upward* — this renderer
/// is the one place that flips, converting once at the point of drawing,
/// the same adapter-at-the-edge pattern `LayoutRect` itself exists for.
enum PDFCueSheetRenderer {
    enum RenderError: Error {
        case couldNotCreateDataConsumer
        case couldNotCreatePDFContext
    }

    static func render(_ pages: [CueSheetPageLayout], to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw RenderError.couldNotCreateDataConsumer
        }
        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: CueSheetLayoutComputer.pageWidth,
            height: CueSheetLayoutComputer.pageHeight
        )
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw RenderError.couldNotCreatePDFContext
        }

        for page in pages {
            context.beginPDFPage(nil)
            draw(page, in: context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    private static func draw(_ page: CueSheetPageLayout, in context: CGContext) {
        let pageHeight = CueSheetLayoutComputer.pageHeight
        for element in page.elements {
            let flippedFrame = CGRect(
                x: element.frame.x,
                y: pageHeight - element.frame.y - element.frame.height,
                width: element.frame.width,
                height: element.frame.height
            )
            switch element.content {
            case let .text(string, font):
                drawText(string, font: font, in: flippedFrame, context: context)
            case let .rule(spec):
                drawRule(spec, in: flippedFrame, context: context)
            }
        }
    }

    private static func drawText(_ string: String, font: LayoutFontSpec, in frame: CGRect, context: CGContext) {
        guard !string.isEmpty else { return }
        let ctFont = CTFontCreateWithName(PDFFontMapping.fontName(for: font.weight) as CFString, font.size, nil)
        let attributedString = NSAttributedString(
            string: string,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: ctFont,
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0, alpha: 1),
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGPath(rect: frame, transform: nil)
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(ctFrame, context)
    }

    private static func drawRule(_ spec: LayoutRuleSpec, in frame: CGRect, context: CGContext) {
        context.setLineWidth(spec.thickness)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.move(to: CGPoint(x: frame.minX, y: frame.midY))
        context.addLine(to: CGPoint(x: frame.maxX, y: frame.midY))
        context.strokePath()
    }
}
